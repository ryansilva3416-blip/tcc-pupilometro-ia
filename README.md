# TCC — Pupilômetro IA

Plataforma para óticas com três módulos:

1. **Medição da distância interpupilar (DP) por fotografia**, com IA (MediaPipe) e calibração por marcador impresso.
2. **Simulação visual de tratamentos de lentes** sobre a foto do cliente *(etapa 3)*.
3. **CRM com lembrete anual por e-mail**: 12 meses após o exame, o cliente recebe um lembrete para refazer o exame *(etapa 4)*.

Universidade Federal do Pará — Campus Tucuruí — Engenharia da Computação.

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `app/` | Aplicativo Flutter (**somente Android**). A visão computacional roda em Kotlin e conversa com o Flutter por Platform Channel. |
| `app/android/app/src/main/kotlin/...` | `AnalisadorImagem.kt`: MediaPipe Face Landmarker (pontos da íris) + OpenCV (marcador ArUco e nitidez). |
| `app/lib/medicao/calculo_dp.dart` | Regra de cálculo da DP e verificações de qualidade (Dart puro, testado). |
| `analysis/` | Implementação de referência em Python (mesmas regras do app), gerador do marcador e, depois, scripts de análise estatística (Bland-Altman). |
| `supabase/` | Banco de dados: tabelas, segurança por ótica (RLS) e regras do CRM. |
| `docs/` | Marcador para impressão e documentação. |

## Estado atual

- [x] Etapa 0 — estrutura, banco de dados inicial, testes automáticos (GitHub Actions)
- [x] Etapa 1 — medição: captura, detecção, calibração, cálculo da DP, verificação de qualidade, registro local e exportação CSV do experimento
- [ ] Etapa 2 — cadastro de clientes e exames integrado ao Supabase
- [ ] Etapa 3 — simulação visual de tratamentos
- [ ] Etapa 4 — CRM: envio dos lembretes por e-mail
- [ ] Etapa 5 — painel da ótica
- [ ] Etapa 6 — avaliação experimental

## Como rodar o app no celular (primeira vez)

Pré-requisitos no computador:

- [Flutter](https://docs.flutter.dev/get-started/install) **3.29 ou mais novo** (`flutter --version`)
- Android Studio (instala o Android SDK); rode `flutter doctor` e resolva o que aparecer em vermelho
- Celular Android 7.0 ou superior com **Depuração USB** ligada (Configurações → Sobre o telefone → toque 7 vezes em "Número da versão" → Opções do desenvolvedor → Depuração USB)

Passo a passo:

```bash
git clone https://github.com/ryansilva3416-blip/tcc-pupilometro-ia.git
cd tcc-pupilometro-ia/app

# Gera os arquivos padrão do Android que não ficam no Git (não sobrescreve os existentes)
flutter create . --platforms=android --org br.ufpa.tcc --project-name pupilometro

flutter pub get
flutter test          # deve passar tudo
flutter run           # com o celular conectado no USB
```

Na primeira compilação o Gradle baixa sozinho o modelo `face_landmarker.task` do MediaPipe (≈ 4 MB). Isso exige internet.

Se aparecer erro, copie a mensagem completa e envie para análise.

## Marcador de calibração

1. Imprima `docs/marcador_40mm_id0.pdf` em **tamanho real (100%)**.
2. Confira com uma régua: a régua impressa tem que medir 50 mm e o quadrado preto, 40 mm.
   Se medir diferente, informe o valor medido em **Configurações → Lado do marcador**.
3. Cole o marcador num papel firme e fixe na testa, centralizado e reto, o mais próximo possível do plano dos olhos.

Para gerar outro tamanho:

```bash
cd analysis
pip install -r requirements.txt
python -m pupilometro.marcador --tamanho-mm 50 --id 0 --saida marcador_50mm.pdf
```

## Como funciona a medição

1. O app tira a foto (câmera traseira por padrão, operada pelo técnico).
2. O Kotlin corrige a orientação da foto, detecta os 478 pontos do rosto com o MediaPipe e localiza o marcador ArUco com o OpenCV (cantos com precisão subpixel).
3. O Dart calcula:
   - **escala** = lado do marcador em mm ÷ lado médio do marcador em pixels
   - **DP (marcador)** = escala × distância entre os centros das íris em pixels
   - **DP (íris)** = distância em pixels × 11,7 mm ÷ diâmetro da íris em pixels (estimativa de comparação)
4. Verificações de qualidade geram **erros** (sem resultado) ou **avisos** (resultado suspeito): sem rosto, mais de um rosto, marcador ausente ou duplicado, cabeça inclinada (> 2°), rosto virado, marcador inclinado ou pequeno, foto tremida, DP fora de 45–80 mm.
   Os limites são iniciais e serão revistos depois do piloto.
5. O técnico informa o código do participante (ex.: P001) e, se quiser, o valor do pupilômetro. A medição é salva no celular e pode ser exportada em CSV na tela **Registros**.

O centro da pupila pode ser calculado de dois jeitos (em **Configurações**): pela média dos 4 pontos do contorno da íris ou pelo ponto central do modelo. O modo usado fica salvo em cada medição, para comparar os dois na análise.

## Banco de dados (Supabase)

As regras do CRM ficam no próprio banco (`supabase/migrations/`):

- Ao cadastrar um exame de cliente que **autorizou lembretes e tem e-mail**, agenda um lembrete para **data do exame + 12 meses** (configurável por ótica).
- Um exame novo cancela os lembretes pendentes do exame anterior.
- Revogar o consentimento ou clicar em "descadastrar" no e-mail cancela os lembretes pendentes.
- Segundo lembrete 15 dias depois, se o cliente não clicou.
- Cada usuário só acessa os dados da própria ótica (RLS).

Testar localmente (precisa de PostgreSQL instalado):

```bash
bash supabase/tests/rodar_testes.sh
```

Aplicar no Supabase (etapa 2):

```bash
npm install -g supabase
supabase init          # só na primeira vez; não apaga as migrations
supabase login
supabase link --project-ref <id-do-projeto>
supabase db push
```

## Testes

| Parte | Comando |
|---|---|
| Cálculo e marcador (Python) | `cd analysis && python -m pytest` |
| Banco de dados | `bash supabase/tests/rodar_testes.sh` |
| App (Dart) | `cd app && flutter test` |

Os três rodam automaticamente no GitHub Actions a cada envio (aba **Actions** do repositório).

## Proteção de dados

- Participantes do experimento são identificados **só por código**.
- Fotos e CSVs com dados de participantes **não** vão para o Git (ver `.gitignore`).
- O exame de vista é dado de saúde (LGPD, dado sensível): no banco, consentimentos são separados (pesquisa × lembretes), com histórico, e o acesso é restrito por ótica.
