##' Bayesian optimization for RandomForest
##'
##' This function estimates parameters for xgboost based on bayesian optimization.
##' @param train_data A data frame for training of xgboost
##' @param train_label The column of class to classify in the training data
##' @param test_data A data frame for training of xgboost
##' @param test_label The column of class to classify in the test data
##' @param num_tree_range The range of the number of trees for forest. Defaults
##'   to 500 (no optimization).
##' @param mtry_range Value of mtry used. Defaults from 1 to number of columns.
##' @param min_node_size_range The range of minimum node sizes to best tested.
##'   Default min is 1 and max is sqrt(nrow(train_data)).
##' @param init_points Number of randomly chosen points to sample the
##'   target function before Bayesian Optimization fitting the Gaussian Process.
##' @param n_iter Total number of times the Bayesian Optimization is to repeated.
##' @param acq Acquisition function type to be used. Can be "ucb", "ei" or "poi".
##' \itemize{
##'   \item \code{ucb} GP Upper Confidence Bound
##'   \item \code{ei} Expected Improvement
##'   \item \code{poi} Probability of Improvement
##' }
##' @param kappa tunable parameter kappa of GP Upper Confidence Bound, to balance exploitation against exploration,
##'   increasing kappa will make the optimized hyperparameters pursuing exploration.
##' @param eps tunable parameter epsilon of Expected Improvement and Probability of Improvement, to balance exploitation against exploration,
##'   increasing epsilon will make the optimized hyperparameters are more spread out across the whole range.
##' @param kernel Kernel (aka correlation function) for the underlying Gaussian Process. This parameter should be a list
##'   that specifies the type of correlation function along with the smoothness parameter. Popular choices are square exponential (default) or matern 5/2
##'
##' @return The test accuracy and a list of Bayesian Optimization result is returned:
##' \itemize{
##'   \item \code{Best_Par} a named vector of the best hyperparameter set found
##'   \item \code{Best_Value} the value of metrics achieved by the best hyperparameter set
##'   \item \code{History} a \code{data.table} of the bayesian optimization history
##'   \item \code{Pred} a \code{data.table} with validation/cross-validation prediction for each round of bayesian optimization history
##' }
##'
##' @import ranger
##' @import rBayesianOptimization
##' @importFrom stats predict
##' @export
rf_opt <- function(train_data,
                   train_label,
                   test_data,
                   test_label,
                   num_tree_range = 500L,
                   mtry_range = c(1L, ncol(train_data)),
                   min_node_size_range = c(1L, as.integer(sqrt(nrow(train_data)))),
                   init_points = 20,
                   n_iter = 1,
                   acq = "ei",
                   kappa = 2.576,
                   eps = 0.0,
                   kernel = list(type = "exponential", power = 2)) {

  dtrain <- train_data
  dtest <- test_data

  if (class(train_label) != "factor") {
    trainlabel <- as.factor(train_label)
  } else {
    trainlabel <- train_label
  }

  if (class(test_label) != "factor") {
    testlabel <- as.factor(train_label)
  } else {
    testlabel <- test_label
  }

  # Ranger does not seem to support Y being a vector outside of the dataframe,
  # so we explicitly add to dataframe with a unique name to avoid conflicts.
  dtrain <- cbind(`_Y` = trainlabel, dtrain)

  rf_holdout <- function(mtry_opt, min_node_size, num_trees = NULL) {
    if (is.null(num_trees)) {
      # Get num_trees default from the calling function.
      #num_trees = get("num_tree_range", envir = parent.frame())
      num_trees = num_tree_range
    }
    model <- ranger(`_Y` ~., dtrain,
                    num.trees = num_trees,
                    min.node.size = min_node_size,
                    mtry = mtry_opt)
    t.pred <- predict(model, dat = dtest)
    Pred <- sum(diag(table(testlabel, t.pred$predictions)))/nrow(dtest)
    list(Score = Pred, Pred = Pred)
  }

  bounds = list(mtry_opt = mtry_range,
                min_node_size = min_node_size_range)

  # Only add to bounds if we are optimizing over num_trees. If it's a single
  # value just pass into ranger() and don't optimize it.
  if (length(num_tree_range) != 1L) {
    bounds[["num_trees"]] <- num_tree_range
  }

  opt_res <- BayesianOptimization(rf_holdout,
                                  bounds = bounds,
                                  init_points,
                                  init_grid_dt = NULL,
                                  n_iter,
                                  acq,
                                  kappa,
                                  eps,
                                  verbose = TRUE)

  return(opt_res)

}
