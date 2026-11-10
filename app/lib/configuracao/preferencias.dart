import 'package:shared_preferences/shared_preferences.dart';

import '../medicao/calculo_dp.dart';

/// Parâmetros ajustáveis pela equipe na tela de configurações.
class Preferencias {
  static const _kTamanho = 'tamanho_marcador_mm';
  static const _kId = 'id_marcador';
  static const _kModo = 'modo_centro';
  static const _kDicionario = 'dicionario_aruco';

  static Future<ConfiguracaoCalculo> carregarCalculo() async {
    final p = await SharedPreferences.getInstance();
    return ConfiguracaoCalculo(
      tamanhoMarcadorMm: p.getDouble(_kTamanho) ?? 40.0,
      idMarcador: p.getInt(_kId) ?? 0,
      modoCentro: ModoCentro.values.byName(p.getString(_kModo) ?? ModoCentro.contorno.name),
    );
  }

  static Future<String> dicionario() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kDicionario) ?? 'DICT_4X4_50';
  }

  static Future<void> salvar({
    required double tamanhoMarcadorMm,
    required int idMarcador,
    required ModoCentro modoCentro,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kTamanho, tamanhoMarcadorMm);
    await p.setInt(_kId, idMarcador);
    await p.setString(_kModo, modoCentro.name);
  }
}
