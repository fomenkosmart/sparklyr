context("ml recommendation - als")

sc <- testthat_spark_connection()

test_that("ml_als param setting", {
  args <- list(
    x = sc, rating_col = "rcol", user_col = "ucol", item_col = "icol",
    rank = 9, reg_param = 0.2, implicit_prefs = TRUE, alpha = 1.1,
    nonnegative = TRUE, max_iter = 7, num_user_blocks = 11,
    num_item_blocks = 11, checkpoint_interval = 9, cold_start_strategy = "drop",
    intermediate_storage_level = "MEMORY_ONLY",
    final_storage_level = "MEMORY_ONLY"
  )
  predictor <- do.call(ml_als, args)
  args_to_check <- if (spark_version(sc) >= "2.2.0")
    setdiff(names(args), "x")
  else
    setdiff(names(args), c("x", "cold_start_strategy"))
  expect_equal(ml_params(predictor, args_to_check), args[args_to_check])
})

test_that("ml_als() default params are correct", {

  predictor <- ml_pipeline(sc) %>%
    ml_als() %>%
    ml_stage(1)

  args <- get_default_args(ml_als,
                           c("x", "uid", "...", "cold_start_strategy"))

  expect_equal(
    ml_params(predictor, names(args)),
    args)
})

test_that("ml_recommend() works", {
  if (spark_version(sc) < "2.2.0") skip("")

  user <- c(0, 0, 1, 1, 2, 2)
  item <- c(0, 1, 1, 2, 1, 2)
  rating <- c(4.0, 2.0, 3.0, 4.0, 1.0, 5.0)

  df <- data.frame(user = user, item = item, rating = rating)
  movie_ratings <- sdf_copy_to(sc, df, "movie_rating", overwrite = TRUE)

  als_model <- ml_als(movie_ratings)
  expect_identical(
    als_model %>%
      ml_recommend("users", 2) %>%
      colnames(),
    c("item", "recommendations", "user", "rating")
  )
  expect_identical(
    als_model %>%
      ml_recommend("items", 2) %>%
      colnames(),
    c("user", "recommendations", "item", "rating")
  )
})
