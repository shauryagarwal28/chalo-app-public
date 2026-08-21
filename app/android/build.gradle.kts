import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

// ===== Agora iris-rtc / agora-special-full namespace-collision fix =====
// See docs/process/build-status.md's "Android build environment" section
// for the full history. Summary: agora_rtc_engine 6.5.4 unconditionally
// depends on two AARs -- io.agora.rtc:iris-rtc (the JNI bridge) and
// io.agora.rtc:agora-special-full (the native engine + .so files) -- and
// both AARs' own AndroidManifest.xml declare package="io.agora.rtc". AGP
// 9.0.1's manifest merger hard-rejects that as a namespace collision on
// :app's main manifest, and there's no supported config flag to relax it
// (confirmed by decompiling ManifestMerger2 -- see the doc). Neither
// coordinate has an alternate version to force; both are exact pins inside
// agora_rtc_engine's own build script.
//
// A same-type ("aar" -> "aar") Gradle Artifact Transform *cannot* fix this:
// Gradle's transform-graph selection always prefers the shortest available
// attribute-transform chain, and AGP itself registers a direct "aar" ->
// "android-manifest" transform (used to extract AndroidManifest.xml for the
// merger, confirmed via AarTransform.class / AndroidArtifacts$ArtifactType
// in gradle-9.0.1.jar). A same-type transform we register ourselves can
// only ever add a *longer* detour (aar -> aar -> android-manifest) than
// AGP's already-registered direct one-hop path, so it would provably never
// be selected -- this isn't a guess, it follows from how Gradle's
// transform-chain selection is documented to work, and matches exactly the
// "silently no-op" failure mode this fix needed to watch for.
//
// Working fix instead, same practical effect (rewrite the AAR before it's
// consumed downstream, without touching Agora's published files): rewrite
// iris-rtc's AndroidManifest.xml package from "io.agora.rtc" to
// "io.agora.rtc.iris" (safe -- its manifest declares no
// activities/services/providers/permissions, just a bare package + minSdk,
// and its actual Java classes live under io.agora.iris, not io.agora.rtc,
// so nothing is bound to this manifest package; confirmed by decompiling
// both the AAR and its libs/AgoraRtcWrapper.jar), then republish the
// patched AAR (same POM content, only the inner manifest changed) into a
// small local Maven repo, under a synthetic version suffix
// ("-namespaced") rather than the original version string.
//
// The synthetic version matters: an earlier attempt published the patch
// under the *same* coordinate (io.agora.rtc:iris-rtc:4.5.3-build.1) and
// just listed the local repo before google()/mavenCentral(), expecting
// repository order to prefer it. That silently failed -- verified by
// building and finding the merge error still referenced the unpatched
// manifest. Root cause: Gradle treats a fixed (non-changing) version as
// immutable once it has *any* cached resolution for that exact coordinate,
// and reuses that cached resolution (and its recorded source repository)
// without re-consulting repository order on later builds, so adding a
// competing repo for an already-resolved fixed version is a no-op. Using a
// version string upstream has never published forces a genuine fresh
// resolution that can only succeed against our local repo, then a
// dependency substitution (below, scoped to `subprojects` only) transparently
// redirects every request for the real coordinate to the synthetic one.
val agoraPatchedRepoDir: File = File(rootDir.parentFile, "build/agora-patched-repo")

fun rezipAar(sourceDir: File, outputAar: File) {
    outputAar.parentFile.mkdirs()
    ZipOutputStream(outputAar.outputStream()).use { zos ->
        sourceDir.walkTopDown().filter { it.isFile }.sortedBy { it.path }.forEach { file ->
            val entryName = file.relativeTo(sourceDir).path.replace(File.separatorChar, '/')
            zos.putNextEntry(ZipEntry(entryName))
            file.inputStream().use { it.copyTo(zos) }
            zos.closeEntry()
        }
    }
}

val agoraIrisGroup = "io.agora.rtc"
val agoraIrisModule = "iris-rtc"
val agoraIrisOriginalVersion = "4.5.3-build.1"
val agoraIrisPatchedVersion = "$agoraIrisOriginalVersion-namespaced"

fun Project.patchAgoraIrisRtcNamespace(agoraPatchedRepoDir: File) {
    // Resolve the real, unmodified AAR from upstream (under its *original*
    // coordinate) via a detached configuration. This project's own
    // `dependencySubstitution` rule (added on `subprojects`, not here on
    // root) doesn't apply to this detached configuration, so this always
    // resolves the genuine upstream artifact, never a copy of our own
    // output -- no risk of "patching an already-patched file" or
    // circularity.
    val detached = configurations.detachedConfiguration(
        dependencies.create("$agoraIrisGroup:$agoraIrisModule:$agoraIrisOriginalVersion")
    )
    val originalAar = detached.resolve().single { it.name.endsWith(".aar") }

    val extractDir = File(agoraPatchedRepoDir.parentFile, "agora-patched/iris-rtc-src")
    extractDir.deleteRecursively()
    copy {
        from(zipTree(originalAar))
        into(extractDir)
    }

    val manifestFile = File(extractDir, "AndroidManifest.xml")
    val originalManifest = manifestFile.readText()
    val patchedManifest = originalManifest.replace(
        "package=\"io.agora.rtc\"",
        "package=\"io.agora.rtc.iris\""
    )
    check(patchedManifest != originalManifest) {
        "Agora iris-rtc namespace patch found nothing to replace -- " +
            "AndroidManifest.xml no longer contains package=\"io.agora.rtc\" " +
            "(Agora may have changed the manifest in a newer release). " +
            "Update or remove this patch in app/android/build.gradle.kts."
    }
    manifestFile.writeText(patchedManifest)

    val groupPath = agoraIrisGroup.replace('.', '/')
    val outputAar = File(
        agoraPatchedRepoDir,
        "$groupPath/$agoraIrisModule/$agoraIrisPatchedVersion/$agoraIrisModule-$agoraIrisPatchedVersion.aar"
    )
    rezipAar(extractDir, outputAar)

    // Same POM Agora publishes for this coordinate (no dependencies of its
    // own, confirmed against the real POM in the Gradle cache) -- only the
    // version and the AAR's inner manifest changed, not the rest of the
    // module's metadata.
    val pomFile = File(
        agoraPatchedRepoDir,
        "$groupPath/$agoraIrisModule/$agoraIrisPatchedVersion/$agoraIrisModule-$agoraIrisPatchedVersion.pom"
    )
    pomFile.writeText(
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <project xmlns="http://maven.apache.org/POM/4.0.0">
            <modelVersion>4.0.0</modelVersion>
            <groupId>$agoraIrisGroup</groupId>
            <artifactId>$agoraIrisModule</artifactId>
            <version>$agoraIrisPatchedVersion</version>
            <packaging>aar</packaging>
        </project>
        """.trimIndent()
    )
}

allprojects {
    repositories {
        // Must come first so it's preferred over the real upstream
        // coordinate -- see the namespace-collision comment above.
        maven { url = uri(agoraPatchedRepoDir) }
        google()
        mavenCentral()
    }
}

// agora_rtc_engine 6.5.4's own AAR -- and its iris_method_channel JNI-bridge
// subproject -- are compiled against API 31 (confirmed 2026-07-10 via a
// throwaway diagnostic task reading `android.compileSdk` off every Flutter
// plugin subproject in this workspace: agora_rtc_engine=31,
// iris_method_channel=31, google_maps_flutter_android=36,
// permission_handler_android=35, share_plus=34,
// flutter_plugin_android_lifecycle=36, jni=35, jni_flutter=35, app=36).
// Several AndroidX libraries pulled in transitively -- directly, and via
// io.flutter:flutter_embedding_debug, which itself depends on modern
// fragment/core/lifecycle/window versions -- declare AAR metadata requiring
// API 33/34+, which fails Gradle's CheckAarMetadata task specifically on
// these two subprojects, regardless of this app's own compileSdk. Upgrading
// agora_rtc_engine to 6.6.2+ (Agora's own fix) is blocked by a separate ffi
// version conflict with share_plus (see docs/process/build-status.md's
// "Android build environment" section).
//
// Fix: force every offending AndroidX artifact down to the newest version
// whose own AAR metadata still declares minCompileSdk <= 31 (verified
// against Google's Maven repo, not guessed -- see docs/process/build-status.md
// for the verification method and what was runtime-tested afterward).
// androidx.window.extensions.core:core has no version <= 31 (1.0.0 is its
// first-ever release and already requires 33) so it's excluded outright;
// window/window-java 1.0.0 don't depend on it, so nothing else pulls it
// back in.
//
// SCOPE (2026-07-10 fix -- this used to be `allprojects`, that was the bug):
// this force must apply *only* to agora_rtc_engine and iris_method_channel's
// own configurations, not to :app's (or any other subproject's). Forcing it
// globally also downgraded :app's own runtime classpath to
// androidx.core:core 1.8.0, and Flutter's own TextInputPlugin.java calls
// `EditorInfoCompat.setStylusHandwritingEnabled` UNCONDITIONALLY on every
// text-field focus -- a method that doesn't exist before androidx.core
// 1.13.0 (confirmed by decompiling core-<version>.aar's classes.jar with
// `javap` for every stable release from 1.8.0 through 1.13.1: 1.9.0/1.10.0/
// 1.10.1 need minCompileSdk 33 and don't have the method; 1.12.0 needs 34
// and still doesn't have it; 1.13.0 is the *first* version with the method,
// and it needs minCompileSdk 34). So forcing :app down to any single
// androidx.core version can't satisfy both "has the method" and
// "minCompileSdk <= 31" at once -- no such version exists. The real fix is
// to stop forcing :app's resolution at all: its own compileSdk is 36
// (comfortably above minCompileSdk 34), so leaving androidx.core unforced
// there lets it naturally resolve to 1.13.1 -- the exact version
// io.flutter:flutter_embedding_debug's own POM requests (confirmed by
// reading that POM directly in the Gradle cache) -- which has the method
// and satisfies CheckAarMetadata. agora_rtc_engine/iris_method_channel still
// need the low-version force for their own (unrelated, unchanged) compileSdk
// 31 constraint, so it stays, just scoped down to only those two projects.
val agoraLowCompileSdkProjectNames = listOf("agora_rtc_engine", "iris_method_channel")
val agoraLowCompileSdkProjects = agoraLowCompileSdkProjectNames.mapNotNull { findProject(":$it") }
check(agoraLowCompileSdkProjects.size == agoraLowCompileSdkProjectNames.size) {
    "Expected to find Gradle subprojects for all of $agoraLowCompileSdkProjectNames but only " +
        "found ${agoraLowCompileSdkProjects.map { it.path }} -- a plugin version bump may have " +
        "renamed/removed one of these subprojects. Re-run the printCompileSdks-style diagnostic " +
        "(see docs/process/build-status.md) to find which subprojects actually need this force " +
        "before assuming it's still just these two."
}

configure(agoraLowCompileSdkProjects) {
    configurations.all {
        resolutionStrategy {
            force(
                "androidx.fragment:fragment:1.5.7",
                "androidx.activity:activity:1.5.1",
                "androidx.window:window:1.0.0",
                "androidx.window:window-java:1.0.0",
                "androidx.core:core:1.8.0",
                "androidx.core:core-ktx:1.8.0",
                "androidx.lifecycle:lifecycle-runtime:2.5.1",
                "androidx.lifecycle:lifecycle-process:2.5.1",
                "androidx.lifecycle:lifecycle-viewmodel:2.5.1",
                "androidx.lifecycle:lifecycle-viewmodel-savedstate:2.5.1",
                "androidx.lifecycle:lifecycle-livedata:2.5.1",
                "androidx.lifecycle:lifecycle-livedata-core:2.5.1",
                "androidx.lifecycle:lifecycle-livedata-core-ktx:2.5.1",
                "androidx.lifecycle:lifecycle-common:2.5.1",
                "androidx.lifecycle:lifecycle-common-java8:2.5.1",
                "androidx.savedstate:savedstate:1.2.0",
                "androidx.tracing:tracing:1.1.0",
                "androidx.exifinterface:exifinterface:1.3.7",
                "androidx.annotation:annotation-experimental:1.2.0",
                "androidx.arch.core:core-runtime:2.1.0",
                "androidx.arch.core:core-common:2.2.0",
                "androidx.profileinstaller:profileinstaller:1.1.0"
            )
        }
        exclude(group = "androidx.window.extensions.core", module = "core")
    }
}

// Runs once per configure, after the `allprojects` block above so this
// (root) project's own `repositories` are already populated. Always
// re-patches (cheap -- one small AAR) rather than caching by a marker
// file, so it can never go stale relative to whatever's in the Gradle
// dependency cache.
project.patchAgoraIrisRtcNamespace(agoraPatchedRepoDir)

// Scoped to `subprojects` (not `allprojects`/root) deliberately -- root's
// own detached configuration above, which fetches the real unpatched
// artifact to patch it, must never be redirected to the (at that moment
// not-yet-fully-consumed) patched coordinate. Every real subproject
// (agora_rtc_engine, :app, etc.) that pulls in iris-rtc transitively gets
// silently redirected to our patched artifact instead.
subprojects {
    configurations.all {
        resolutionStrategy.dependencySubstitution {
            substitute(module("$agoraIrisGroup:$agoraIrisModule:$agoraIrisOriginalVersion"))
                .using(module("$agoraIrisGroup:$agoraIrisModule:$agoraIrisPatchedVersion"))
                .because(
                    "namespace collision fix -- see the comment above the " +
                        "patchAgoraIrisRtcNamespace() function in this file"
                )
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
