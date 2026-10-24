plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// Server the app talks to. Production is fixed; a debug build can point at a
// local skedd, e.g. -PskedServerUrl=http://10.0.2.2:1984 for the emulator.
val skedServerUrl = providers.gradleProperty("skedServerUrl").orElse("https://rasp.relya.ru").get()

android {
    namespace = "ru.sked.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "ru.sked.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 4
        versionName = "0.4.0"
        buildConfigField("String", "SERVER_URL", "\"https://rasp.relya.ru\"")
    }

    buildTypes {
        debug {
            buildConfigField("String", "SERVER_URL", "\"$skedServerUrl\"")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            // Installable without a release key; sign with your own key to publish.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    androidResources {
        generateLocaleConfig = false
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons)

    testImplementation(libs.junit)
    testImplementation(libs.org.json)
}
