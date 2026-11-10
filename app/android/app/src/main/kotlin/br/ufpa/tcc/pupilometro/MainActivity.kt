package br.ufpa.tcc.pupilometro

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Ponte entre o Flutter e o código nativo de visão computacional.
 *
 * Canal: "br.ufpa.tcc.pupilometro/visao"
 *  - analisarImagem(caminho: String, dicionarioAruco: String) -> Map com pontos faciais,
 *    marcadores ArUco, nitidez e tempos de processamento (ver AnalisadorImagem).
 *  - versao() -> Map com versões das bibliotecas, para registro nos experimentos.
 *
 * Todo o processamento roda em uma única thread de fundo, fora da thread da interface.
 */
class MainActivity : FlutterActivity() {

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())

    // Acessado somente dentro do executor.
    private var analisador: AnalisadorImagem? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL).setMethodCallHandler { chamada, resultado ->
            when (chamada.method) {
                "analisarImagem" -> {
                    val caminho = chamada.argument<String>("caminho")
                    val dicionario = chamada.argument<String>("dicionarioAruco") ?: "DICT_4X4_50"
                    if (caminho.isNullOrBlank()) {
                        resultado.error("ARGUMENTO_INVALIDO", "Caminho da imagem não informado.", null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        try {
                            val a = analisador ?: AnalisadorImagem(applicationContext).also { analisador = it }
                            val mapa = a.analisar(caminho, dicionario)
                            principal.post { resultado.success(mapa) }
                        } catch (e: Throwable) {
                            principal.post {
                                resultado.error("FALHA_ANALISE", e.message ?: e.javaClass.simpleName, null)
                            }
                        }
                    }
                }

                "versao" -> resultado.success(AnalisadorImagem.versoes())

                else -> resultado.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        executor.execute {
            analisador?.fechar()
            analisador = null
        }
        executor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CANAL = "br.ufpa.tcc.pupilometro/visao"
    }
}
