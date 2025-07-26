plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.autonomiq.obdapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.autonomiq.obdapp"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug") // TODO: Update with release signing config
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Import the Firebase BoM (use latest stable version)
    implementation(platform("com.google.firebase:firebase-bom:33.2.0"))

    // Firebase dependencies (no versions specified with BoM)
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")

    // Add Google Play Services base for GoogleApiManager
    implementation("com.google.android.gms:play-services-base:18.5.0")
}