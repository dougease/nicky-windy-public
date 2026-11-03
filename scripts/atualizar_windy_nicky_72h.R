# ============================================================
# NICKY OOH - GERADOR AUTOMATICO PARA WINDY
# Versao 1.4 - mantém a publicação atual e acrescenta janelas de 72 h
# ============================================================
# Fluxo recomendado:
#   atualizar_ecmwf.R -> atualizar_gefs.R -> este script
#
# Esta versao so publica uma nova fotografia operacional quando
# ECMWF E GEFS tiverem mudado desde a ultima publicacao concluida.
# Isso evita combinar uma rodada nova de um modelo com dados antigos
# do outro modelo caso uma tarefa do Agendador atrase ou falhe.
# ============================================================

options(timeout = max(600, getOption("timeout")))

pacotes <- c("readxl", "dplyr", "jsonlite")
ausentes <- pacotes[!pacotes %in% rownames(installed.packages())]
if (length(ausentes) > 0) install.packages(ausentes, dependencies = TRUE)

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
})

pasta_dados <- Sys.getenv(
  "NICKY_ANALYTICS_DIR",
  unset = "C:/Users/Douglas/Documents/NICKY OOH/Climatologia"
)

arquivo_base <- file.path(pasta_dados, "paineis_analytics_atual.xlsx")
arquivo_base_fallback <- file.path(pasta_dados, "paineis_analytics.xlsx")
arquivo_ecmwf <- file.path(pasta_dados, "paineis_previsao_3.xlsx")
arquivo_gefs <- file.path(pasta_dados, "paineis_previsao_gefs.xlsx")
arquivo_ecmwf_janelas <- file.path(pasta_dados, "previsao_rajadas_ecmwf_janelas.csv")
arquivo_gefs_janelas <- file.path(pasta_dados, "previsao_rajadas_gefs_janelas.csv")

pasta_app <- file.path(pasta_dados, "Nicky_Analytics_Shiny")
pasta_windy <- file.path(pasta_app, "www", "windy")
arquivo_geojson <- file.path(pasta_windy, "paineis_nicky.geojson")

# Repositório público separado. NÃO publique a pasta Nicky_Analytics_Shiny.
pasta_repo_publico <- Sys.getenv(
  "NICKY_WINDY_PUBLIC_REPO",
  unset = file.path(pasta_dados, "Nicky_Windy_Public", "automacao", "repo")
)
gerador_72h <- file.path(pasta_repo_publico, "scripts", "gerar_windy_72h.R")
arquivo_json_72h <- file.path(pasta_dados, "risco_72h.json")
# Destino remoto: dougease/nicky-windy-public, main, paineis_nicky.geojson
arquivo_estado <- file.path(pasta_dados, "estado_alertas_meteorologicos.csv")
arquivo_eventos <- file.path(pasta_dados, "historico_alertas_meteorologicos.csv")
arquivo_estado_publicacao <- file.path(pasta_dados, "estado_publicacao_windy.csv")

modulo_candidatos <- c(
  file.path(pasta_dados, "nicky_windy_monitoramento.R"),
  file.path(getwd(), "nicky_windy_monitoramento.R")
)
modulo <- modulo_candidatos[file.exists(modulo_candidatos)][1]
if (is.na(modulo) || length(modulo) == 0) {
  stop("nicky_windy_monitoramento.R não encontrado na pasta Climatologia.")
}
source(modulo, local = TRUE, encoding = "UTF-8")

ler_excel <- function(caminho) {
  if (!file.exists(caminho)) return(data.frame())
  as.data.frame(readxl::read_excel(caminho, sheet = 1))
}

mtime_num <- function(caminho) {
  if (!file.exists(caminho)) return(NA_real_)
  as.numeric(file.info(caminho)$mtime)
}

ler_estado_publicacao <- function() {
  if (!file.exists(arquivo_estado_publicacao)) return(NULL)
  tryCatch(
    utils::read.csv(arquivo_estado_publicacao, stringsAsFactors = FALSE),
    error = function(e) NULL
  )
}

gravar_estado_publicacao <- function(ecmwf_mtime, gefs_mtime, rodada_ecmwf, rodada_gefs,
                                    git_publicado, janelas_ecmwf_mtime = NA_real_,
                                    janelas_gefs_mtime = NA_real_) {
  estado <- data.frame(
    PUBLICADO_EM = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "America/Sao_Paulo"),
    ECMWF_MTIME = ecmwf_mtime,
    GEFS_MTIME = gefs_mtime,
    ECMWF_JANELAS_MTIME = janelas_ecmwf_mtime,
    GEFS_JANELAS_MTIME = janelas_gefs_mtime,
    RODADA_ECMWF_UTC = as.character(rodada_ecmwf %||% ""),
    RODADA_GEFS_UTC = as.character(rodada_gefs %||% ""),
    GIT_PUBLICADO = as.integer(isTRUE(git_publicado)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(estado, arquivo_estado_publicacao, row.names = FALSE, fileEncoding = "UTF-8")
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

# Publicação Git pode ser habilitada depois do baseline local.
publicar_git <- identical(Sys.getenv("NICKY_WINDY_GIT_PUBLISH", unset = "1"), "1")

# Publicador sem IA, chamado pelo mesmo agendamento que gera o GeoJSON.
publicar_geojson_github <- function() {
  script_publicador <- file.path(pasta_dados, "sincronizar-windy.ps1")
  if (!file.exists(script_publicador)) stop("Publicador ausente: ", script_publicador)
  powershell <- file.path(Sys.getenv("SystemRoot", "C:/Windows"),
                          "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
  pasta_trabalho <- dirname(pasta_repo_publico)
  status <- system2(powershell, c(
    "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
    "-File", shQuote(script_publicador),
    "-Source", shQuote(arquivo_geojson),
    "-JsonSource", shQuote(arquivo_json_72h),
    "-WorkingDirectory", shQuote(pasta_trabalho)
  ), stdout = "", stderr = "")
  identical(as.integer(status), 0L)
}

gerar_json_72h <- function() {
  if (!file.exists(gerador_72h)) stop("Gerador ausente: ", gerador_72h)
  modo_anterior <- Sys.getenv("NICKY_WINDY_GIT_PUBLISH", unset = NA_character_)
  saida_anterior <- Sys.getenv("NICKY_WINDY_JSON_OUT", unset = NA_character_)
  Sys.setenv(NICKY_WINDY_GIT_PUBLISH = "0", NICKY_WINDY_JSON_OUT = arquivo_json_72h)
  on.exit({
    if (is.na(modo_anterior)) Sys.unsetenv("NICKY_WINDY_GIT_PUBLISH")
    else Sys.setenv(NICKY_WINDY_GIT_PUBLISH = modo_anterior)
    if (is.na(saida_anterior)) Sys.unsetenv("NICKY_WINDY_JSON_OUT")
    else Sys.setenv(NICKY_WINDY_JSON_OUT = saida_anterior)
  })
  source(gerador_72h, local = new.env(parent = globalenv()), encoding = "UTF-8")
  if (!file.exists(arquivo_json_72h)) stop("Gerador não produziu o JSON.")
}
# ============================================================
# 1. PRE-CHECAGEM DOS ARQUIVOS DE MODELO
# ============================================================

if (!file.exists(arquivo_ecmwf)) stop("Arquivo ECMWF não encontrado: ", arquivo_ecmwf)
if (!file.exists(arquivo_gefs)) stop("Arquivo GEFS não encontrado: ", arquivo_gefs)
if (!file.exists(arquivo_ecmwf_janelas)) stop("CSV ECMWF não encontrado: ", arquivo_ecmwf_janelas)
if (!file.exists(arquivo_gefs_janelas)) stop("CSV GEFS não encontrado: ", arquivo_gefs_janelas)

mtime_ecmwf <- mtime_num(arquivo_ecmwf)
mtime_gefs <- mtime_num(arquivo_gefs)
mtime_ecmwf_janelas <- mtime_num(arquivo_ecmwf_janelas)
mtime_gefs_janelas <- mtime_num(arquivo_gefs_janelas)
estado_publicacao <- ler_estado_publicacao()

ultimo_mtime <- function(coluna) {
  if (is.null(estado_publicacao) || !nrow(estado_publicacao) ||
      !coluna %in% names(estado_publicacao)) return(NA_real_)
  suppressWarnings(as.numeric(tail(estado_publicacao[[coluna]], 1)))
}
novas_janelas <- !file.exists(arquivo_json_72h) ||
  (!is.finite(ultimo_mtime("ECMWF_JANELAS_MTIME")) ||
   mtime_ecmwf_janelas > ultimo_mtime("ECMWF_JANELAS_MTIME") + 0.5) &&
  (!is.finite(ultimo_mtime("GEFS_JANELAS_MTIME")) ||
   mtime_gefs_janelas > ultimo_mtime("GEFS_JANELAS_MTIME") + 0.5)

# Na primeira execução, aceita os dois arquivos atuais e cria o baseline.
# Nas seguintes, ambos precisam ter sido modificados depois da publicação anterior.
pronto_para_publicar <- TRUE
if (!is.null(estado_publicacao) && nrow(estado_publicacao) > 0 &&
    all(c("ECMWF_MTIME", "GEFS_MTIME") %in% names(estado_publicacao))) {
  ultimo_ecmwf <- suppressWarnings(as.numeric(tail(estado_publicacao$ECMWF_MTIME, 1)))
  ultimo_gefs <- suppressWarnings(as.numeric(tail(estado_publicacao$GEFS_MTIME, 1)))

  ecmwf_novo <- is.finite(mtime_ecmwf) && (!is.finite(ultimo_ecmwf) || mtime_ecmwf > ultimo_ecmwf + 0.5)
  gefs_novo <- is.finite(mtime_gefs) && (!is.finite(ultimo_gefs) || mtime_gefs > ultimo_gefs + 0.5)

  ultimo_git_publicado <- if ("GIT_PUBLICADO" %in% names(estado_publicacao)) {
    suppressWarnings(as.integer(tail(estado_publicacao$GIT_PUBLICADO, 1)))
  } else {
    0L
  }
  precisa_primeira_publicacao_git <- publicar_git && !identical(ultimo_git_publicado, 1L)

  pronto_para_publicar <- isTRUE(ecmwf_novo) && isTRUE(gefs_novo)

  if (precisa_primeira_publicacao_git && !(ecmwf_novo && gefs_novo)) {
    message("Windy: ha envio pendente; sera usada a fotografia GeoJSON existente, sem misturar novas rodadas.")
  }

  if (!pronto_para_publicar) {
    message("Windy: publicação adiada porque os dois modelos ainda não foram atualizados desde a última publicação.")
    message("ECMWF novo: ", ecmwf_novo, " | modificado em: ", format(file.info(arquivo_ecmwf)$mtime, "%d/%m/%Y %H:%M:%S"))
    message("GEFS novo: ", gefs_novo, " | modificado em: ", format(file.info(arquivo_gefs)$mtime, "%d/%m/%Y %H:%M:%S"))
    message("Nenhum GeoJSON público, estado de alerta ou histórico foi alterado nesta execução.")
  }
}

if (pronto_para_publicar) {
  base_atual <- if (file.exists(arquivo_base)) arquivo_base else arquivo_base_fallback
  amostra_base <- if (file.exists(base_atual)) {
    tryCatch(readxl::read_excel(base_atual, sheet = "PAINEIS_ANALYTICS",
                               n_max = 1), error = function(e) NULL)
  } else NULL
  if (is.null(amostra_base) || !nrow(amostra_base) ||
      !all(c("code", "latitude", "longitude") %in% names(amostra_base))) {
    message("Planilha de painéis sem coordenadas: fotografia GeoJSON preservada.")
    pronto_para_publicar <- FALSE
  }
}
if (novas_janelas && !pronto_para_publicar) {
  # Atualiza só as janelas; não reescreve alertas, histórico nem o GeoJSON.
  gerar_json_72h()
  if (publicar_git) {
    if (!publicar_geojson_github()) stop("Publicação de 72 h falhou.")
  }
  gravar_estado_publicacao(
    ultimo_mtime("ECMWF_MTIME"), ultimo_mtime("GEFS_MTIME"),
    if ("RODADA_ECMWF_UTC" %in% names(estado_publicacao))
      tail(estado_publicacao$RODADA_ECMWF_UTC, 1) else "",
    if ("RODADA_GEFS_UTC" %in% names(estado_publicacao))
      tail(estado_publicacao$RODADA_GEFS_UTC, 1) else "",
    git_publicado = publicar_git,
    janelas_ecmwf_mtime = mtime_ecmwf_janelas,
    janelas_gefs_mtime = mtime_gefs_janelas
  )
  message("Windy: janelas de 72 h publicadas sem alterar a fotografia operacional.")
}
if (pronto_para_publicar) {
  # Valida o conjunto sincronizado antes de mexer no estado dos alertas.
  gerar_json_72h()
  # ============================================================
  # 2. LER BASE E PREVISOES
  # ============================================================

  base_caminho <- if (file.exists(arquivo_base)) arquivo_base else arquivo_base_fallback
  if (!file.exists(base_caminho)) stop("Base de painéis não encontrada.")

  base <- tryCatch(
    as.data.frame(readxl::read_excel(base_caminho, sheet = "PAINEIS_ANALYTICS")),
    error = function(e) as.data.frame(readxl::read_excel(base_caminho, sheet = 1))
  )

  if (!all(c("code", "latitude", "longitude") %in% names(base))) {
    stop("A base precisa conter code, latitude e longitude.")
  }
  base$code <- trimws(as.character(base$code))

  preparar_modelo <- function(caminho, prefixo) {
    d <- ler_excel(caminho)
    if (nrow(d) == 0 || !"code" %in% names(d)) return(data.frame(code = character()))
    d$code <- trimws(as.character(d$code))
    probs <- grep("^PROB_RAJADA_[0-9]+KMH_0_24H$", names(d), value = TRUE)
    manter <- unique(c(
      "code", probs,
      intersect(c("ATUALIZADO_EM", "RODADA_ECMWF_UTC", "RODADA_GEFS_UTC"), names(d))
    ))
    d <- d[, manter, drop = FALSE]
    nomes <- names(d)
    nomes[nomes %in% probs] <- paste0(prefixo, "_", nomes[nomes %in% probs])
    if (prefixo == "ECMWF") {
      nomes[nomes == "ATUALIZADO_EM"] <- "ECMWF_ATUALIZADO_EM"
    } else {
      nomes[nomes == "ATUALIZADO_EM"] <- "GEFS_ATUALIZADO_EM"
    }
    names(d) <- nomes
    d[!duplicated(d$code, fromLast = TRUE), , drop = FALSE]
  }

  ecmwf <- preparar_modelo(arquivo_ecmwf, "ECMWF")
  gefs <- preparar_modelo(arquivo_gefs, "GEFS")

  if (nrow(ecmwf) == 0) stop("ECMWF vazio ou inválido; publicação cancelada.")
  if (nrow(gefs) == 0) stop("GEFS vazio ou inválido; publicação cancelada.")

  # Retira previsões antigas da base para impedir sufixos .x/.y nos joins.
  remover <- grep(
    "^(PROB_RAJADA_|ECMWF_PROB_RAJADA_|GEFS_PROB_RAJADA_|ECMWF_ATUALIZADO_EM$|GEFS_ATUALIZADO_EM$|RODADA_ECMWF_UTC$|RODADA_GEFS_UTC$)",
    names(base), value = TRUE
  )
  base <- base[, setdiff(names(base), remover), drop = FALSE]

  base <- dplyr::left_join(base, ecmwf, by = "code")
  base <- dplyr::left_join(base, gefs, by = "code")

  # Confirma que os 197/quantidade atual de painéis não foi reduzida por erro de join.
  if (nrow(base) == 0) stop("A integração resultou em base vazia; publicação cancelada.")

  # ============================================================
  # 3. RISCO, EVENTOS E GEOJSON
  # ============================================================

  base <- nicky_adicionar_risco_operacional(base)
  eventos <- nicky_atualizar_eventos(base, arquivo_estado, arquivo_eventos)
  nicky_gerar_geojson(base, arquivo_geojson)

  resumo <- nicky_resumo_risco(base)
  message("GeoJSON Windy atualizado: ", arquivo_geojson)
  message("Painéis processados: ", nrow(base))
  message("Resumo de risco:")
  print(resumo, row.names = FALSE)
  if (nrow(eventos) > 0) {
    message("Mudanças de risco nesta execução: ", nrow(eventos))
    print(eventos, row.names = FALSE)
  } else {
    message("Nenhuma mudança de nível de risco nesta execução.")
  }

  # ============================================================
  # 4. PUBLICAÇÃO OPCIONAL NO GITHUB
  # ============================================================

  publicacao_git_ok <- !publicar_git
  if (publicar_git) {
    publicacao_git_ok <- publicar_geojson_github()
  }
  if (publicar_git && !publicacao_git_ok) {
    stop("GitHub: envio nao confirmado. O estado de publicacao nao foi avancado; a proxima execucao tentara novamente.")
  }
  # ============================================================
  # 5. MARCAR SINCRONIZAÇÃO SOMENTE APÓS SUCESSO
  # ============================================================

  if (publicacao_git_ok) {
    rodada_ecmwf <- if ("RODADA_ECMWF_UTC" %in% names(ecmwf)) unique(na.omit(ecmwf$RODADA_ECMWF_UTC))[1] else ""
    rodada_gefs <- if ("RODADA_GEFS_UTC" %in% names(gefs)) unique(na.omit(gefs$RODADA_GEFS_UTC))[1] else ""
    gravar_estado_publicacao(
      mtime_ecmwf, mtime_gefs, rodada_ecmwf, rodada_gefs,
      git_publicado = publicar_git && publicacao_git_ok,
      janelas_ecmwf_mtime = mtime_ecmwf_janelas,
      janelas_gefs_mtime = mtime_gefs_janelas
    )
    message("Windy: estado de sincronização atualizado com sucesso.")
  }
}
