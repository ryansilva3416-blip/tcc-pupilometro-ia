package br.ufpa.tcc.pupilometro

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.SystemClock
import androidx.exifinterface.media.ExifInterface
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfDouble
import org.opencv.imgproc.Imgproc
import org.opencv.objdetect.ArucoDetector
import org.opencv.objdetect.DetectorParameters
import org.opencv.objdetect.Objdetect
import java.io.File
import java.io.FileOutputStream

/**
 * Analisa uma foto e devolve dados brutos para o cálculo da distância interpupilar,
 * que é feito no lado Dart (lib/medicao/calculo_dp.dart).
 *
 * Este código NÃO calcula a DP: apenas detecta. Assim a regra de cálculo fica em um
 * só lugar, testável e igual à implementação de referência em Python (analysis/).
 *
 * Mapa devolvido:
 *  - caminhoNormalizado: String  -> JPEG já rotacionado conforme EXIF (é a imagem a exibir/guardar)
 *  - largura, altura: Int        -> dimensões da imagem normalizada, em pixels
 *  - quantidadeRostos: Int
 *  - pontosRosto: DoubleArray?   -> 478 pontos do primeiro rosto, [x0, y0, z0, x1, y1, z1, ...]
 *                                    x e y em PIXELS; z na escala relativa do MediaPipe
 *  - matrizRosto: DoubleArray?   -> matriz 4x4 de transformação facial do MediaPipe (16 valores)
 *  - marcadores: List<Map>       -> [{id: Int, cantos: DoubleArray(8)}], cantos em pixels,
 *                                    ordem do OpenCV: sup-esq, sup-dir, inf-dir, inf-esq
 *  - nitidez: Double             -> variância do Laplaciano da imagem em tons de cinza
 *  - tempoRostoMs, tempoMarcadorMs, tempoTotalMs: Long
 */
class AnalisadorImagem(private val contexto: Context) {

    private val faceLandmarker: FaceLandmarker

    init {
        check(OpenCVLoader.initLocal()) { "Não foi possível carregar o OpenCV." }

        val opcoes = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath(MODELO).build())
            .setRunningMode(RunningMode.IMAGE)
            // Pede até 2 rostos só para poder AVISAR quando houver mais de uma pessoa na foto.
            .setNumFaces(2)
            .setMinFaceDetectionConfidence(0.5f)
            .setMinFacePresenceConfidence(0.5f)
            .setOutputFacialTransformationMatrixes(true)
            .build()
        faceLandmarker = FaceLandmarker.createFromOptions(contexto, opcoes)
    }

    fun analisar(caminho: String, nomeDicionario: String): Map<String, Any?> {
        val inicio = SystemClock.elapsedRealtime()

        val bitmap = carregarNormalizado(caminho)
        val caminhoNormalizado = salvarNormalizado(bitmap, caminho)
        val largura = bitmap.width
        val altura = bitmap.height

        // 1) Pontos faciais e da íris (MediaPipe)
        val t0 = SystemClock.elapsedRealtime()
        val resultado = faceLandmarker.detect(BitmapImageBuilder(bitmap).build())
        val tempoRosto = SystemClock.elapsedRealtime() - t0

        val rostos = resultado.faceLandmarks()
        var pontos: DoubleArray? = null
        if (rostos.isNotEmpty()) {
            val primeiro = rostos[0]
            val arr = DoubleArray(primeiro.size * 3)
            for ((i, p) in primeiro.withIndex()) {
                arr[i * 3] = p.x().toDouble() * largura
                arr[i * 3 + 1] = p.y().toDouble() * altura
                arr[i * 3 + 2] = p.z().toDouble()
            }
            pontos = arr
        }
        var matriz: DoubleArray? = null
        val matrizes = resultado.facialTransformationMatrixes()
        if (matrizes.isPresent && matrizes.get().isNotEmpty()) {
            matriz = matrizes.get()[0].map { it.toDouble() }.toDoubleArray()
        }

        // 2) Marcador ArUco e nitidez (OpenCV)
        val t1 = SystemClock.elapsedRealtime()
        val rgba = Mat()
        val cinza = Mat()
        Utils.bitmapToMat(bitmap, rgba)
        Imgproc.cvtColor(rgba, cinza, Imgproc.COLOR_RGBA2GRAY)
        val marcadores = detectarMarcadores(cinza, nomeDicionario)
        val nitidez = varianciaLaplaciano(cinza)
        val tempoMarcador = SystemClock.elapsedRealtime() - t1
        rgba.release()
        cinza.release()
        bitmap.recycle()

        return mapOf(
            "caminhoNormalizado" to caminhoNormalizado,
            "largura" to largura,
            "altura" to altura,
            "quantidadeRostos" to rostos.size,
            "pontosRosto" to pontos,
            "matrizRosto" to matriz,
            "marcadores" to marcadores,
            "nitidez" to nitidez,
            "tempoRostoMs" to tempoRosto,
            "tempoMarcadorMs" to tempoMarcador,
            "tempoTotalMs" to (SystemClock.elapsedRealtime() - inicio),
        )
    }

    fun fechar() {
        faceLandmarker.close()
    }

    /** Lê a foto e aplica a rotação/espelhamento indicados no EXIF. */
    private fun carregarNormalizado(caminho: String): Bitmap {
        val opcoes = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        val original = BitmapFactory.decodeFile(caminho, opcoes)
            ?: throw IllegalArgumentException("Não foi possível abrir a imagem: $caminho")

        val orientacao = ExifInterface(caminho).getAttributeInt(
            ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL
        )
        val m = Matrix()
        when (orientacao) {
            ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.preScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.preScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { m.postRotate(90f); m.preScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { m.postRotate(270f); m.preScale(-1f, 1f) }
            else -> return original
        }
        val girado = Bitmap.createBitmap(original, 0, 0, original.width, original.height, m, true)
        if (girado !== original) original.recycle()
        return girado
    }

    /** Salva a imagem normalizada para que o Flutter exiba exatamente o que foi analisado. */
    private fun salvarNormalizado(bitmap: Bitmap, caminhoOriginal: String): String {
        val nome = "norm_" + File(caminhoOriginal).nameWithoutExtension + ".jpg"
        val arquivo = File(contexto.cacheDir, nome)
        FileOutputStream(arquivo).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it) }
        return arquivo.absolutePath
    }

    private fun detectarMarcadores(cinza: Mat, nomeDicionario: String): List<Map<String, Any>> {
        val dicionario = Objdetect.getPredefinedDictionary(codigoDicionario(nomeDicionario))
        val parametros = DetectorParameters()
        // Refinamento subpixel dos cantos: importante, pois o erro do canto vira erro de escala.
        parametros.set_cornerRefinementMethod(Objdetect.CORNER_REFINE_SUBPIX)
        val detector = ArucoDetector(dicionario, parametros)

        val cantos = ArrayList<Mat>()
        val ids = Mat()
        detector.detectMarkers(cinza, cantos, ids)

        val lista = ArrayList<Map<String, Any>>()
        for (i in cantos.indices) {
            val c = cantos[i]
            val valores = FloatArray(8)
            c.get(0, 0, valores)
            lista.add(
                mapOf(
                    "id" to ids.get(i, 0)[0].toInt(),
                    "cantos" to valores.map { it.toDouble() }.toDoubleArray(),
                )
            )
            c.release()
        }
        ids.release()
        return lista
    }

    private fun varianciaLaplaciano(cinza: Mat): Double {
        val lap = Mat()
        Imgproc.Laplacian(cinza, lap, CvType.CV_64F)
        val media = MatOfDouble()
        val desvio = MatOfDouble()
        Core.meanStdDev(lap, media, desvio)
        val d = desvio.get(0, 0)[0]
        lap.release(); media.release(); desvio.release()
        return d * d
    }

    companion object {
        private const val MODELO = "face_landmarker.task"

        fun versoes(): Map<String, String> = mapOf(
            "mediapipeTasksVision" to "0.10.21",
            "opencv" to "4.10.0",
            "modelo" to "face_landmarker float16 v1",
        )

        fun codigoDicionario(nome: String): Int = when (nome) {
            "DICT_4X4_50" -> Objdetect.DICT_4X4_50
            "DICT_4X4_100" -> Objdetect.DICT_4X4_100
            "DICT_5X5_50" -> Objdetect.DICT_5X5_50
            "DICT_5X5_100" -> Objdetect.DICT_5X5_100
            "DICT_6X6_50" -> Objdetect.DICT_6X6_50
            else -> throw IllegalArgumentException("Dicionário ArUco não suportado: $nome")
        }
    }
}
