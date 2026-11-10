plugins {
    id("com.android.application")
    id("kotlin-android")
    // O plugin do Flutter precisa vir depois dos plugins do Android e do Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "br.ufpa.tcc.pupilometro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "br.ufpa.tcc.pupilometro"
        // MediaPipe Tasks e OpenCV exigem Android 7.0 (API 24) ou superior.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    androidResources {
        // O modelo do MediaPipe precisa ficar sem compressão dentro do APK.
        noCompress += listOf("task")
    }

    buildTypes {
        release {
            // Protótipo de pesquisa: assina com a chave de debug.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Detecção de pontos faciais e da íris (478 pontos).
    implementation("com.google.mediapipe:tasks-vision:0.10.21")
    // Detecção do marcador ArUco de calibração e métrica de nitidez.
    implementation("org.opencv:opencv:4.10.0")
    // Leitura da orientação (EXIF) das fotos da câmera.
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}

// Baixa o modelo do MediaPipe na primeira compilação (não fica no Git).
val modeloFaceLandmarker = file("src/main/assets/face_landmarker.task")
val urlModelo =
    "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"

val baixarModeloMediapipe by tasks.registering {
    description = "Baixa o modelo face_landmarker.task do MediaPipe, se ainda não existir."
    outputs.file(modeloFaceLandmarker)
    doLast {
        if (!modeloFaceLandmarker.exists()) {
            modeloFaceLandmarker.parentFile.mkdirs()
            logger.lifecycle("Baixando modelo do MediaPipe para ${modeloFaceLandmarker.path} ...")
            uri(urlModelo).toURL().openStream().use { entrada ->
                modeloFaceLandmarker.outputStream().use { saida -> entrada.copyTo(saida) }
            }
        }
    }
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(baixarModeloMediapipe)
}
