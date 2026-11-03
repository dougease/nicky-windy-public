# Nicky OOH: publica classificacoes por janela para o mapa Windy proprio.
# Execute DEPOIS de atualizar_ecmwf_3.R e atualizar_gefs.R.
# Requer readxl e jsonlite. Publicacao Git opcional: NICKY_WINDY_GIT_PUBLISH=1.

suppressPackageStartupMessages({
  library(readxl)
  library(jsonlite)
})

argumentos_execucao <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
pasta_script <- if (length(argumentos_execucao)) {
  dirname(normalizePath(sub("^--file=", "", argumentos_execucao[[1]]),
    winslash = "/", mustWork = FALSE))
} else getwd()
repo_padrao <- if (basename(pasta_script) == "scripts") {
  dirname(pasta_script)
} else file.path(pasta_script, "Nicky_Windy_Public")
pasta_dados <- Sys.getenv("NICKY_ANALYTICS_DIR", unset = dirname(repo_padrao))
pasta_repo <- Sys.getenv("NICKY_WINDY_PUBLIC_REPO", unset = repo_padrao)
pasta_publica <- file.path(pasta_repo, "docs", "windy")
arquivo_saida <- file.path(pasta_publica, "risco_72h.json")
arquivo_ecmwf <- file.path(pasta_dados, "previsao_rajadas_ecmwf_janelas.csv")
arquivo_gefs <- file.path(pasta_dados, "previsao_rajadas_gefs_janelas.csv")
arquivo_base <- file.path(pasta_dados, "paineis_analytics_atual.xlsx")
if (!file.exists(arquivo_base)) {
  arquivo_base <- file.path(pasta_dados, "paineis_analytics.xlsx")
}
arquivo_pagina <- file.path(pasta_publica, "index.html")

for (caminho in c(arquivo_ecmwf, arquivo_gefs, arquivo_base)) {
  if (!file.exists(caminho)) stop("Arquivo necessario ausente: ", caminho)
}
if (!file.exists(arquivo_pagina)) {
  stop("Copie windy_72h.html para ", arquivo_pagina, " antes de executar.")
}

ler_modelo <- function(caminho, modelo) {
  d <- utils::read.csv(caminho, colClasses = c(code = "character"),
    stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8")
  campos <- c("code", "MODELO", "RODADA_UTC", "INICIO_H", "FIM_H",
    "VALIDO_DE_UTC", "VALIDO_ATE_UTC", "P36", "P54", "P90")
  if (!nrow(d) || !all(campos %in% names(d)) ||
      anyNA(d[campos]) || any(d$MODELO != modelo)) {
    stop("CSV ", modelo, " incompleto; nenhuma publicacao efetuada.")
  }
  if (modelo == "GEFS" && !all(c("P63", "P72", "P81") %in% names(d))) {
    stop("CSV GEFS sem P63/P72/P81.")
  }
  d$code <- trimws(as.character(d$code))
  if (any(!nzchar(d$code))) stop("Codigo de painel vazio no ", modelo)
  d$INICIO_H <- suppressWarnings(as.integer(d$INICIO_H))
  d$FIM_H <- suppressWarnings(as.integer(d$FIM_H))
  probabilidades <- c("P36", "P54", "P90")
  if (modelo == "GEFS") probabilidades <- c("P36", "P54", "P63", "P72", "P81", "P90")
  for (nome in probabilidades) d[[nome]] <- suppressWarnings(as.numeric(d[[nome]]))
  if (anyNA(d[c("INICIO_H", "FIM_H", probabilidades)]) ||
      any(!is.finite(as.matrix(d[probabilidades]))) ||
      any(as.matrix(d[probabilidades]) < 0 | as.matrix(d[probabilidades]) > 100) ||
      any(apply(d[probabilidades], 1, function(x) any(diff(as.numeric(x)) > 0)))) {
    stop("Probabilidades invalidas no ", modelo)
  }
  if (length(unique(d$RODADA_UTC)) != 1L ||
      anyDuplicated(d[c("code", "INICIO_H", "FIM_H")]) ||
      any(table(d$code) != 3L) ||
      !setequal(paste(d$INICIO_H, d$FIM_H), c("0 24", "24 48", "48 72"))) {
    stop("Rodadas, paineis ou janelas inconsistentes no ", modelo)
  }
  rodada <- as.POSIXct(d$RODADA_UTC[[1]], format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
  idade_h <- as.numeric(difftime(Sys.time(), rodada, units = "hours"))
  if (is.na(idade_h) || idade_h > 36 || idade_h < -1) {
    stop("Rodada ", modelo, " vencida ou futura; nenhuma publicacao efetuada.")
  }
  esperado_de <- format(rodada + d$INICIO_H * 3600,
    "%Y-%m-%d %H:%M:%S", tz = "UTC")
  esperado_ate <- format(rodada + d$FIM_H * 3600,
    "%Y-%m-%d %H:%M:%S", tz = "UTC")
  if (any(d$VALIDO_DE_UTC != esperado_de | d$VALIDO_ATE_UTC != esperado_ate)) {
    stop("Datas de validade inconsistentes no ", modelo)
  }
  d
}

e <- ler_modelo(arquivo_ecmwf, "ECMWF")
g <- ler_modelo(arquivo_gefs, "GEFS")
if (!identical(e$RODADA_UTC[[1]], g$RODADA_UTC[[1]])) {
  stop("Rodadas UTC diferentes entre ECMWF e GEFS. Aguardar sincronizacao.")
}

base <- tryCatch(
  as.data.frame(readxl::read_excel(arquivo_base, sheet = "PAINEIS_ANALYTICS")),
  error = function(err) as.data.frame(readxl::read_excel(arquivo_base, sheet = 1)))
if (!all(c("code", "latitude", "longitude") %in% names(base))) {
  stop("Base precisa conter code, latitude e longitude.")
}
base$code <- trimws(as.character(base$code))
numero <- function(x) suppressWarnings(as.numeric(gsub(",", ".", as.character(x), fixed = TRUE)))
base$latitude <- numero(base$latitude)
base$longitude <- numero(base$longitude)
if (!nrow(base) || anyNA(base[c("code", "latitude", "longitude")]) ||
    any(!nzchar(base$code)) || anyDuplicated(base$code) ||
    any(base$latitude < -90 | base$latitude > 90 | base$longitude < -180 |
        base$longitude > 180)) {
  stop("Codigos ou coordenadas ausentes, invalidos ou duplicados na base.")
}
if (!setequal(base$code, e$code) || !setequal(base$code, g$code)) {
  stop("Os painéis ativos diferem dos CSVs; aguardando atualização de ambos os modelos.")
}

chaves <- c("code", "INICIO_H", "FIM_H", "RODADA_UTC", "VALIDO_DE_UTC", "VALIDO_ATE_UTC")
d <- merge(e, g, by = chaves, suffixes = c("_ECMWF", "_GEFS"), all = FALSE, sort = FALSE)
if (nrow(d) != 3L * nrow(base)) {
  stop("Os modelos nao cobrem igualmente todos os paineis e janelas.")
}

classificar <- function(p54, p90) {
  if (p90 >= 10) return(list(nivel = "Verificar ≥90 km/h", cor = "#C94C4C"))
  if (p54 >= 30) return(list(nivel = "Verificar ≥54 km/h", cor = "#E85D04"))
  list(nivel = "Acompanhar", cor = "#2E8B57")
}

janelas <- lapply(c(0L, 24L, 48L), function(inicio) {
  linhas <- d[d$INICIO_H == inicio, , drop = FALSE]
  linhas <- linhas[match(base$code, linhas$code), , drop = FALSE]
  if (anyNA(linhas$code)) stop("Painel sem janela ", inicio, "–", inicio + 24)
  paineis <- lapply(seq_len(nrow(base)), function(i) {
    p54 <- max(linhas$P54_ECMWF[[i]], linhas$P54_GEFS[[i]])
    p90 <- max(linhas$P90_ECMWF[[i]], linhas$P90_GEFS[[i]])
    classe <- classificar(p54, p90)
    list(code = base$code[[i]], lat = base$latitude[[i]], lon = base$longitude[[i]],
      nivel = classe$nivel, cor = classe$cor,
      ecmwf54 = linhas$P54_ECMWF[[i]], gefs54 = linhas$P54_GEFS[[i]],
      ecmwf90 = linhas$P90_ECMWF[[i]], gefs90 = linhas$P90_GEFS[[i]])
  })
  list(inicioH = inicio, fimH = inicio + 24L,
    validoDeUTC = linhas$VALIDO_DE_UTC[[1]],
    validoAteUTC = linhas$VALIDO_ATE_UTC[[1]], paineis = paineis)
})

payload <- list(versao = 1L, rodadaUTC = e$RODADA_UTC[[1]],
  atualizadoUTC = format(max(file.info(c(arquivo_ecmwf, arquivo_gefs))$mtime),
    "%Y-%m-%d %H:%M:%S", tz = "UTC"),
  quantidade = nrow(base), janelas = janelas)
dir.create(pasta_publica, recursive = TRUE, showWarnings = FALSE)
temporario <- tempfile("nicky_72h_", tmpdir = pasta_publica, fileext = ".json")
jsonlite::write_json(payload, temporario, auto_unbox = TRUE, pretty = TRUE,
  na = "null", null = "null")
if (file.exists(arquivo_saida)) {
  backup <- paste0(arquivo_saida, ".bak")
  if (file.exists(backup)) unlink(backup)
  if (!file.rename(arquivo_saida, backup)) stop("Arquivo JSON em uso; publicação cancelada.")
  if (!file.rename(temporario, arquivo_saida)) {
    file.rename(backup, arquivo_saida)
    stop("Falha ao substituir JSON; arquivo anterior recuperado.")
  }
  unlink(backup)
} else if (!file.rename(temporario, arquivo_saida)) {
  stop("Falha ao publicar JSON.")
}
message("Mapa Windy preparado: ", nrow(base), " paineis × 3 janelas, rodada ",
  payload$rodadaUTC, " UTC")

if (identical(Sys.getenv("NICKY_WINDY_GIT_PUBLISH", unset = "0"), "1")) {
  git <- Sys.which("git")
  if (!nzchar(git) || !dir.exists(file.path(pasta_repo, ".git"))) {
    stop("JSON local pronto, mas repositório Git público ou git indisponível.")
  }
  git_run <- function(args) {
    out <- suppressWarnings(system2(git, c("-C", shQuote(pasta_repo), args),
      stdout = TRUE, stderr = TRUE))
    status <- attr(out, "status")
    if (is.null(status)) status <- 0L
    if (status != 0L) stop("Falha Git (", status, "): ", paste(out, collapse = "\n"))
    out
  }
  git_run(c("add", "--", "docs/windy/index.html", "docs/windy/risco_72h.json"))
  alterado <- suppressWarnings(system2(git,
    c("-C", shQuote(pasta_repo), "diff", "--cached", "--quiet", "--",
      "docs/windy/index.html", "docs/windy/risco_72h.json"),
    stdout = FALSE, stderr = FALSE))
  if (identical(as.integer(alterado), 1L)) {
    git_run(c("commit", "-m", shQuote(paste("Atualiza risco Windy 72h", payload$rodadaUTC))))
    git_run(c("push", "origin", "HEAD:main"))
    message("Mapa e janelas publicados no repositorio Git.")
  } else if (identical(as.integer(alterado), 0L)) {
    message("Mapa sem alterações; nenhum commit necessário.")
  } else stop("Nao foi possivel conferir as alteracoes Git.")
}
