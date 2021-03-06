context("ml feature (transformers)")

sc <- testthat_spark_connection()

# Tokenizer

test_that("We can instantiate tokenizer object", {
  tokenizer <- ft_tokenizer(sc, "x", "y", uid = "tok")
  expect_equal(jobj_class(spark_jobj(tokenizer), simple_name = FALSE)[1], "org.apache.spark.ml.feature.Tokenizer")
  expect_equal(tokenizer$uid, "tok")
  expect_equal(class(tokenizer), c("ml_tokenizer", "ml_transformer", "ml_pipeline_stage"))
})


test_that("ft_tokenizer() returns params of transformer", {
  tokenizer <- ft_tokenizer(sc, "x", "y")
  expected_params <- list("x", "y")
  expect_true(dplyr::setequal(ml_param_map(tokenizer), expected_params))
})

test_that("ft_tokenizer.tbl_spark() works as expected", {
  # skip_on_cran()
  test_requires("janeaustenr")
  austen     <- austen_books()
  austen_tbl <- testthat_tbl("austen")

  spark_tokens <- austen_tbl %>%
    na.omit() %>%
    filter(length(text) > 0) %>%
    head(10) %>%
    ft_tokenizer("text", "tokens") %>%
    sdf_read_column("tokens") %>%
    lapply(unlist)

  r_tokens <- austen %>%
    filter(nzchar(text)) %>%
    head(10) %>%
    `$`("text") %>%
    tolower() %>%
    strsplit("\\s")

  expect_identical(spark_tokens, r_tokens)
})

# Binarizer

test_that("ft_binarizer() returns params of transformer", {
  binarizer <- ft_binarizer(sc, "x", "y", threshold = 0.5)
  params <- list("x", "y", threshold = 0.5)
  expect_true(dplyr::setequal(ml_param_map(binarizer), params))
})

test_that("ft_binarizer.tbl_spark() works as expected", {
  test_requires("dplyr")
  df <- data.frame(id = 0:2L, feature = c(0.1, 0.8, 0.2))
  df_tbl <- copy_to(sc, df, overwrite = TRUE)
  expect_equal(
    df_tbl %>%
      ft_binarizer("feature", "binarized_feature", threshold = 0.5) %>%
      collect(),
    df %>%
      mutate(binarized_feature = c(0.0, 1.0, 0.0))
  )
})

test_that("ft_binarizer() threshold defaults to 0", {
  expect_identical(ft_binarizer(sc, "in", "out") %>%
                     ml_param("threshold"),
                   0)
})

test_that("ft_binarizer() input checking works", {
  expect_identical(ft_binarizer(sc, "in", "out", 1L) %>%
                     ml_param("threshold") %>%
                     class(),
                   "numeric")
  expect_error(ft_binarizer(sc, "in", "out", "foo"),
               "length-one numeric vector")

  bin <- ft_binarizer(sc, "in", "out", threshold = 10)
  expect_equal(ml_params(bin, list("input_col", "output_col", "threshold")),
               list(input_col = "in", output_col = "out", threshold = 10))
})

# HashingTF

test_that("ft_hashing_tf() works", {
  expect_identical(ft_hashing_tf(sc, "in", "out", num_features = 25) %>%
                     ml_param("num_features") %>%
                     class(),
                   "integer")
  expect_error(ft_hashing_tf(sc, "in", "out", binary = 1),
               "length-one logical vector")

  htf <- ft_hashing_tf(sc, "in", "out", binary = TRUE, num_features = 1024)

  expect_equal(
    ml_params(htf, list("input_col", "output_col", "binary", "num_features")),
    list(input_col = "in", output_col = "out", binary = TRUE, num_features = 1024)
  )

  htf <- ft_hashing_tf(sc, "in", "out")

  expect_equal(
    ml_params(htf, list("input_col", "output_col", "binary", "num_features")),
    list(input_col = "in", output_col = "out", binary = FALSE, num_features = 2^18)
  )
})

# IndexToString

test_that("ft_index_to_string() works", {
  df <- dplyr::data_frame(string = c("foo", "bar", "foo", "foo"))
  df_tbl <- dplyr::copy_to(sc, df, overwrite = TRUE)

  s1 <- df_tbl %>%
    ft_string_indexer("string", "indexed") %>%
    ft_index_to_string("indexed", "string2") %>%
    dplyr::pull(string2)

  expect_identical(s1, c("foo", "bar", "foo", "foo"))

  s2 <- df_tbl %>%
    ft_string_indexer("string", "indexed") %>%
    ft_index_to_string("indexed", "string2", c("wow", "cool")) %>%
    dplyr::pull(string2)

  expect_identical(s2, c("wow", "cool", "wow", "wow"))

  its <- ft_index_to_string(sc, "indexed", "string", labels = list("foo", "bar"))

  expect_equal(
    ml_params(its, list("input_col", "output_col", "labels")),
    list(input_col = "indexed",
         output_col = "string",
         labels = list("foo", "bar"))
  )
})

# ElementwiseProduct

test_that("ft_elementwise_product() works", {
  df <- data.frame(a = 1, b = 3, c = 5)
  df_tbl <- dplyr::copy_to(sc, df, overwrite = TRUE)

  nums <- df_tbl %>%
    ft_vector_assembler(list("a", "b", "c"), output_col = "features") %>%
    ft_elementwise_product("features", "multiplied", c(2, 4, 6)) %>%
    dplyr::pull(multiplied) %>%
    rlang::flatten_dbl()

  expect_identical(nums,
                   c(1, 3, 5) * c(2, 4, 6))

  ewp <- ft_elementwise_product(
    sc, "features", "multiplied", scaling_vec = c(1, 3, 5))

  expect_equal(
    ml_params(ewp, list(
      "input_col", "output_col", "scaling_vec"
    )),
    list(input_col = "features",
         output_col = "multiplied",
         scaling_vec = c(1, 3, 5))
  )


})

# RegexTokenizer

test_that("ft_regex_tokenizer() works", {
  test_requires("dplyr")
  sentence_df <- data_frame(
    id = c(0, 1, 2),
    sentence = c("Hi I heard about Spark",
                 "I wish Java could use case classes",
                 "Logistic,regression,models,are,neat")
  )
  sentence_tbl <- testthat_tbl("sentence_df")

  expect_identical(
    sentence_tbl %>%
      ft_regex_tokenizer("sentence", "words", pattern = "\\W") %>%
      collect() %>%
      mutate(words = sapply(words, length)) %>%
      pull(words),
    c(5L, 7L, 5L))

  rt <- ft_regex_tokenizer(
    sc, "sentence", "words",
    gaps = TRUE, min_token_length = 2, pattern = "\\W", to_lower_case = FALSE)

  expect_equal(
    ml_params(rt, list(
      "input_col", "output_col", "gaps", "min_token_length", "pattern", "to_lower_case"
    )),
    list(input_col = "sentence",
         output_col = "words",
         gaps = TRUE,
         min_token_length = 2L,
         pattern = "\\W",
         to_lower_case = FALSE)
  )

})

# StopWordsRemover

test_that("ft_stop_words_remover() works", {
  test_requires("dplyr")
  df <- data_frame(id = c(0, 1),
                   raw = c("I saw the red balloon", "Mary had a little lamb"))
  df_tbl <- copy_to(sc, df, overwrite = TRUE)

  expect_identical(
    df_tbl %>%
      ft_tokenizer("raw", "words") %>%
      ft_stop_words_remover("words", "filtered") %>%
      pull(filtered),
    list(list("saw", "red", "balloon"), list("mary", "little", "lamb"))
  )

  expect_identical(
    df_tbl %>%
      ft_tokenizer("raw", "words") %>%
      ft_stop_words_remover("words", "filtered", stop_words = list("I", "Mary", "lamb")) %>%
      pull(filtered),
    list(list("saw", "the", "red", "balloon"), list("had", "a", "little"))
  )

  swr <- ft_stop_words_remover(
    sc, "input", "output", case_sensitive = TRUE,
    stop_words = as.list(letters), uid = "hello")

  expect_equal(
    ml_params(swr, list(
    "input_col", "output_col", "case_sensitive", "stop_words")),
    list(input_col = "input",
         output_col = "output",
         case_sensitive = TRUE,
         stop_words = as.list(letters))
  )
})
