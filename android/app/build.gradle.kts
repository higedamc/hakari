import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (gitignored) points at the
// keystore. Falls back to debug signing when absent (e.g. CI).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// Cargokit: builds the Rust core (rust/) and bundles librust.so per ABI.
apply(from = "../../cargokit/gradle/plugin.gradle")

extensions.configure<Any>("cargokit") {
    this.javaClass.getMethod("setManifestDir", String::class.java).invoke(this, "../../rust")
    this.javaClass.getMethod("setLibname", String::class.java).invoke(this, "rust")
}

android {
    namespace = "org.lekt.hakari"
    compileSdk = flutter.compileSdkVersion
    // Pinned to match rust/.cargo/config.toml Android linker paths.
    ndkVersion = "28.0.13004108"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }


    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.lekt.hakari"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // health (Health Connect) requires API 26+.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Cargokit copies lib<name>.so into build/app/jniLibs/<variant>/<abi>/.
    // Newer AGP ignores sourceSet srcDirs added lazily by the cargokit
    // plugin, so register them statically here.
    // AGP 9 rejects Provider instances in the SourceSet API, so resolve
    // the directories eagerly (buildDirectory is already final here).
    sourceSets {
        getByName("debug") {
            jniLibs.srcDir(layout.buildDirectory.dir("jniLibs/debug").get().asFile)
        }
        getByName("profile") {
            jniLibs.srcDir(layout.buildDirectory.dir("jniLibs/profile").get().asFile)
        }
        getByName("release") {
            jniLibs.srcDir(layout.buildDirectory.dir("jniLibs/release").get().asFile)
        }
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
