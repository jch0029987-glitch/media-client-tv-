import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties for release signing if it exists
def keystorePropertiesFile = rootProject.file("key.properties")
def keystoreProperties = new Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.media_client_tv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.media_client_tv"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        release {
            if (keystoreProperties.containsKey('storeFile')) {
                storeFile = file(keystoreProperties.getProperty('storeFile'))
                storePassword = keystoreProperties.getProperty('storePassword')
                keyAlias = keystoreProperties.getProperty('keyAlias')
                keyPassword = keystoreProperties.getProperty('keyPassword')
            }
        }
    }

    buildTypes {
        release {
            // Use the release signing config if available, fallback to debug otherwise
            signingConfig = keystoreProperties.containsKey('storeFile') ? signingConfigs.getByName("release") : signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
