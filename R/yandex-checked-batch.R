# Internal wrapper over the native checked robotstxtyandex batch binding
# (ROBO-jbhtvilo, YI4b). Not exported. It gives the terse-named native routine
# `robotstxtr_checked_batch_()` a readable, self-documenting signature for
# tests and for the Yandex matcher adapter (match_yandex_v1(),
# R/match-yandex-v1.R), which the `yandex` backend is registered with since
# YI5.
#
# Each distinct body is parsed exactly once. `bodies` is a list of raw vectors
# (the DISTINCT robots bodies, bytes preserved verbatim); `body_index` is a
# 1-based integer, one per row, selecting which body that row uses;
# `product_tokens` is a character vector of product tokens, one per row;
# `targets` is a list of raw vectors carrying the exact request-target bytes,
# one per row. The names are the ones the batch module (R/matcher-batch-v1.R)
# calls every native batch with.
#
# Returns the native per-row result columns unchanged (see the TU header for the
# full surface), plus the scalar `n_parse_calls`.
yandex_evaluate_checked_batch <- function(bodies, body_index, product_tokens,
                                          targets) {
  robotstxtr_checked_batch_(
    bodies = bodies,
    ids = as.integer(body_index),
    agents = as.character(product_tokens),
    targets = targets
  )
}
