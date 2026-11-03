# ============================================================
# NICKY OOH - GERADOR AUTOMATICO PARA WINDY
# Versao 1.3 - GeoJSON e janelas de risco 72 h no mesmo agendamento
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
  unset = file.path(pasta_dados, "Nicky_Windy_Public")
)
destino_geojson_publico <- file.path(
  pasta_repo_publico, "docs", "windy", "paineis_nicky.geojson"
)
destino_json_72h <- file.path(pasta_repo_publico, "docs", "windy", "risco_72h.json")
gerador_72h <- file.path(pasta_repo_publico, "scripts", "gerar_windy_72h.R")
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
                                    git_publicado, ecmwf_janelas_mtime, gefs_janelas_mtime) {
  estado <- data.frame(
    PUBLICADO_EM = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "America/Sao_Paulo"),
    ECMWF_MTIME = ecmwf_mtime,
    GEFS_MTIME = gefs_mtime,
    ECMWF_JANELAS_MTIME = ecmwf_janelas_mtime,
    GEFS_JANELAS_MTIME = gefs_janelas_mtime,
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
publicar_git <- identical(Sys.getenv("NICKY_WINDY_GIT_PUBLISH", unset = "0"), "1")

# ============================================================
# 1. PRE-CHECAGEM DOS ARQUIVOS DE MODELO
# ============================================================

if (!file.exists(arquivo_ecmwf)) stop("Arquivo ECMWF não encontrado: ", arquivo_ecmwf)
if (!file.exists(arquivo_gefs)) stop("Arquivo GEFS não encontrado: ", arquivo_gefs)
if (!file.exists(arquivo_ecmwf_janelas)) stop("Janelas ECMWF não encontradas: ", arquivo_ecmwf_janelas)
if (!file.exists(arquivo_gefs_janelas)) stop("Janelas GEFS não encontradas: ", arquivo_gefs_janelas)
if (!file.exists(gerador_72h)) stop("Gerador de 72 h não encontrado: ", gerador_72h)

mtime_ecmwf <- mtime_num(arquivo_ecmwf)
mtime_gefs <- mtime_num(arquivo_gefs)
mtime_ecmwf_janelas <- mtime_num(arquivo_ecmwf_janelas)
mtime_gefs_janelas <- mtime_num(arquivo_gefs_janelas)
estado_publicacao <- ler_estado_publicacao()

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

  pronto_para_publicar <- (isTRUE(ecmwf_novo) && isTRUE(gefs_novo)) ||
    isTRUE(precisa_primeira_publicacao_git)

  if (precisa_primeira_publicacao_git && !(ecmwf_novo && gefs_novo)) {
    message("Windy: publicação Git ainda não inicializada; será usado o baseline local atual para o primeiro envio público.")
  }

  if (!pronto_para_publicar) {
    message("Windy: publicação adiada porque os dois modelos ainda não foram atualizados desde a última publicação.")
    message("ECMWF novo: ", ecmwf_novo, " | modificado em: ", format(file.info(arquivo_ecmwf)$mtime, "%d/%m/%Y %H:%M:%S"))
    message("GEFS novo: ", gefs_novo, " | modificado em: ", format(file.info(arquivo_gefs)$mtime, "%d/%m/%Y %H:%M:%S"))
    message("A fotografia do GeoJSON não mudou; verificando se há novas janelas de 72 h.")
  }
}

ultimo_ecmwf_janelas <- if (!is.null(estado_publicacao) && nrow(estado_publicacao) > 0 &&
    "ECMWF_JANELAS_MTIME" %in% names(estado_publicacao)) {
  suppressWarnings(as.numeric(tail(estado_publicacao$ECMWF_JANELAS_MTIME, 1)))
} else NA_real_
ultimo_gefs_janelas <- if (!is.null(estado_publicacao) && nrow(estado_publicacao) > 0 &&
    "GEFS_JANELAS_MTIME" %in% names(estado_publicacao)) {
  suppressWarnings(as.numeric(tail(estado_publicacao$GEFS_JANELAS_MTIME, 1)))
} else NA_real_
janelas_novas <- !file.exists(destino_json_72h) ||
  (is.finite(mtime_ecmwf_janelas) && is.finite(mtime_gefs_janelas) &&
   (!is.finite(ultimo_ecmwf_janelas) ||
      mtime_ecmwf_janelas > ultimo_ecmwf_janelas + 0.5) &&
   (!is.finite(ultimo_gefs_janelas) ||
      mtime_gefs_janelas > ultimo_gefs_janelas + 0.5))
pronto_para_publicar <- pronto_para_publicar || janelas_novas

if (pronto_para_publicar) {
  # Validar e gerar o JSON ANTES de alterar os alertas e o histórico.
  # O gerador não faz push aqui: os dois arquivos públicos seguem no mesmo commit.
  modo_git_anterior <- Sys.getenv("NICKY_WINDY_GIT_PUBLISH", unset = NA_character_)
  Sys.setenv(NICKY_WINDY_GIT_PUBLISH = "0")
  tryCatch(
    source(gerador_72h, local = new.env(parent = globalenv()), encoding = "UTF-8"),
    finally = if (is.na(modo_git_anterior)) {
      Sys.unsetenv("NICKY_WINDY_GIT_PUBLISH")
    } else {
      Sys.setenv(NICKY_WINDY_GIT_PUBLISH = modo_git_anterior)
    }
  )
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
    git <- Sys.which("git")
    if (!nzchar(git)) {
      warning("Git não encontrado; GeoJSON local gerado, mas publicação pública não concluída.")
      publicacao_git_ok <- FALSE
    } else if (!dir.exists(file.path(pasta_repo_publico, ".git"))) {
      warning(
        "Repositório público Git não encontrado em: ", pasta_repo_publico,
        ". Inicialize primeiro o repositório nicky-windy-public."
      )
      publicacao_git_ok <- FALSE
    } else {
      dir.create(dirname(destino_geojson_publico), recursive = TRUE, showWarnings = FALSE)
      copiado <- file.copy(arquivo_geojson, destino_geojson_publico, overwrite = TRUE)
      if (!isTRUE(copiado)) {
        warning("Não foi possível copiar o GeoJSON para o repositório público.")
        publicacao_git_ok <- FALSE
      }

      run_git <- function(args, stdout = TRUE, stderr = TRUE) {
        system2(
          git,
          c("-C", shQuote(pasta_repo_publico), args),
          stdout = stdout, stderr = stderr
        )
      }

      if (isTRUE(copiado)) {
        run_git(c("add", "--", "docs/windy/paineis_nicky.geojson",
                  "docs/windy/risco_72h.json"))
      }
      status_cached <- if (isTRUE(copiado)) {
        suppressWarnings(system2(
          git,
          c("-C", shQuote(pasta_repo_publico), "diff", "--cached", "--quiet",
            "--", "docs/windy/paineis_nicky.geojson", "docs/windy/risco_72h.json"),
          stdout = FALSE, stderr = FALSE
        ))
      } else {
        2L
      }

      publicacao_git_ok <- isTRUE(copiado)
      if (isTRUE(copiado) && !identical(status_cached, 0L)) {
        msg <- paste0("Atualiza risco Windy - ", format(Sys.time(), "%Y-%m-%d %H:%M"))
        saida_commit <- run_git(c("commit", "-m", shQuote(msg), "--",
                                 "docs/windy/paineis_nicky.geojson", "docs/windy/risco_72h.json"))
        message(paste(saida_commit, collapse = "\n"))

        branch <- tryCatch(
          trimws(run_git(c("rev-parse", "--abbrev-ref", "HEAD"))[[1]]),
          error = function(e) "main"
        )
        if (!nzchar(branch) || branch == "HEAD") branch <- "main"

        saida_push <- tryCatch(
          run_git(c("push", "origin", paste0("HEAD:", branch))),
          warning = function(w) structure(conditionMessage(w), status = 1L),
          error = function(e) structure(conditionMessage(e), status = 1L)
        )
        status_push <- attr(saida_push, "status")
        if (is.null(status_push)) status_push <- 0L
        message(paste(saida_push, collapse = "\n"))
        publicacao_git_ok <- identical(as.integer(status_push), 0L)

        if (!publicacao_git_ok) {
          warning("Git push não foi concluído; o estado de publicação não será avançado.")
        }
      } else {
        message("GitHub: GeoJSON sem alteração de conteúdo relevante para commit.")
      }
    }
  }

  if (publicar_git && isTRUE(publicacao_git_ok)) {
    message("GitHub: publicação pública concluída no repositório dedicado.")
    message("Arquivo publicado relativo: docs/windy/paineis_nicky.geojson")
    message("Arquivo publicado relativo: docs/windy/risco_72h.json")
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
      ecmwf_janelas_mtime = mtime_ecmwf_janelas,
      gefs_janelas_mtime = mtime_gefs_janelas
    )
    message("Windy: estado de sincronização atualizado com sucesso.")
  }
}
