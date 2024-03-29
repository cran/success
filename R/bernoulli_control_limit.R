#' @title Determine control limits for the Bernoulli CUSUM by simulation
#'
#' @description This function can be used to determine control limits for the
#' Bernoulli CUSUM (\code{\link[success]{bernoulli_cusum}}) procedure by
#' restricting the type I error \code{alpha} of the
#' procedure over \code{time}.
#'
#' @details This function performs 3 steps to determine a suitable control limit.
#' \itemize{
#' \item Step 1: Generates \code{n_sim} in-control units (failure rate as baseline).
#' If \code{data} is provided, subject covariates are resampled from the data set.
#' \item Step 2: Determines chart values for all simulated units.
#' \item Step 3: Determines control limits such that at most a proportion \code{alpha}
#' of all units cross the control limit.
#' } The generated data as well as the charts are also returned in the output.
#'
#'
#' @inheritParams bernoulli_cusum
#' @param time A numeric value over which the type I error \code{alpha} must be restricted.
#' @param alpha A proportion between 0 and 1 indicating the required maximal type I error.
#' @param psi A numeric value indicating the estimated Poisson arrival rate of subjects
#' at their respective units. Can be determined using
#' \code{\link[success:parameter_assist]{parameter_assist()}}.
#' @param n_sim An integer value indicating the amount of units to generate for the
#' determination of the control limit. Larger values yield more precise control limits,
#' but increase computation times. Default is 200.
#' @param baseline_data (optional): A \code{data.frame} used for covariate resampling
#' with rows representing subjects and at least the
#' following named columns: \describe{
#'   \item{\code{entrytime}:}{time of entry into study (numeric);}
#'   \item{\code{survtime}:}{time from entry until event (numeric);}
#'   \item{\code{censorid}:}{censoring indicator (0 = right censored, 1 = observed),
#'    (integer).}
#' } and optionally additional covariates used for risk-adjustment. Can only be specified
#'  in combination with \code{coxphmod}.
#' @param h_precision (optional): A numerical value indicating how precisely the control limit
#' should be determined. By default, control limits will be determined up to 2 significant digits.
#' @param seed (optional): A numeric seed for survival time generation.
#' Default is 01041996 (my birthday).
#' @param pb (optional): A boolean indicating whether a progress bar should
#' be shown. Default is \code{FALSE}.
#'
#'
#' @return A list containing three components:
#' \itemize{
#' \item \code{call}: the call used to obtain output;
#' \item \code{charts}: A list of length \code{n_sim} containing the constructed charts;
#' \item \code{data}: A \code{data.frame} containing the in-control generated data.
#' \item \code{h}: Determined value of the control limit.
#' }
# There are \code{\link[success:plot.success]{plot}} and
#  \code{\link[success:runlength.success]{runlength}} methods for "success" objects.
#'
#' @export
#'
#' @author Daniel Gomon
#' @family control limit simulation
#' @seealso \code{\link[success]{bernoulli_cusum}}
#'
#'
#' @examples
#' #We consider patient outcomes 100 days after their entry into the study.
#' followup <- 100
#'
#' #Determine a risk-adjustment model using a generalized linear model.
#' #Outcome (failure within 100 days) is regressed on the available covariates:
#' exprfitber <- as.formula("(survtime <= followup) & (censorid == 1)~ age + sex + BMI")
#' glmmodber <- glm(exprfitber, data = surgerydat, family = binomial(link = "logit"))
#'
#' #Determine control limit restricting type I error to 0.1 over 500 days
#' #using the risk-adjusted glm constructed on the baseline data.
#' a <- bernoulli_control_limit(time = 500, alpha = 0.1, followup = followup,
#'  psi = 0.5, n_sim = 10, theta = log(2), glmmod = glmmodber, baseline_data = surgerydat)
#'
#' print(a$h)





bernoulli_control_limit <- function(time, alpha = 0.05, followup, psi,
                                    n_sim = 200,
                                    glmmod, baseline_data, theta, p0, p1,
                                    h_precision = 0.01,
                                    seed = 1041996, pb = FALSE, assist){
  #This function consists of 3 steps:
  #1. Constructs n_sim instances (hospitals) with subject arrival rate psi and
  #   cumulative baseline hazard cbaseh. Possibly by resampling subject charac-
  #   teristics from data and risk-adjusting using coxphmod.
  #2. Construct the CGR-CUSUM chart for each hospital until timepoint time
  #3. Determine control limit h such that at most proportion alpha of the
  #   instances will produce a signal.
  unit <- NULL
  set.seed(seed)
  if(!missing(assist)){
    list2env(assist, envir = environment())
  }
  call = match.call()

  #Time must be positive and numeric
  if(!all(is.numeric(time), length(time) == 1, time > 0)){
    stop("Argument time must be a single positive numeric value.")
  }

  #alpha must be between 0 and 1
  if(!all(is.numeric(alpha), length(alpha) == 1, alpha > 0, alpha < 1)){
    stop("Argument alpha must be a single numeric value between 0 and 1.")
  }

  #Check that followup is a numeric value greater than 0
  if(!all(is.numeric(followup), length(followup) == 1, followup > 0)){
    stop("Argument followup must be a single numeric value larger than 0.")
  }

  #Check that psi is a numeric value greater than 0
  if(!all(is.numeric(psi), length(psi) == 1, psi > 0)){
    stop("Argument psi must be a single numeric value larger than 0.")
  }

  #Check that n_sim is a numeric value greater than 0
  if(!all(n_sim%%1 == 0, length(n_sim) == 1, n_sim > 0)){
    stop("Argument n_sim must be a single integer value larger than 0.")
  }

  if(time <= followup){
    stop("Argument followup must be greater than time, otherwise no events will be observed.")
  }

  #First we generate the n_sim unit data
  if(pb) { message("Step 1/3: Generating in-control data.")}
  df_temp <- generate_units_bernoulli(time = time, psi = psi, n_sim = n_sim,
                                      p0 = p0, p1 = p1, theta = theta, glmmod = glmmod,
                                      followup = followup,
                            baseline_data = baseline_data)

  if(pb){ message("Step 2/3: Determining Bernoulli CUSUM chart(s).")}

  #Construct for each unit a Bernoulli CUSUM until time
  charts <- list(length = n_sim)
  if(pb){
    pbbar <- pbapply::timerProgressBar(min = 1, max = n_sim)
    on.exit(close(pbbar))
  }

  for(j in 1:n_sim){
    if(pb){
      pbapply::setTimerProgressBar(pbbar, value = j)
    }
    charts[[j]] <- bernoulli_cusum(data = subset(df_temp, unit == j),
                                   followup = followup, theta = theta,
                                   glmmod = glmmod,
                                   p0 = p0, p1 = p1, stoptime = time)
  }



  if(pb){ message("Step 3/3: Determining control limits")}

  #Create a sequence of control limit values h to check for
  #start from 0.1 to maximum value of all CGR-CUSUMS
  CUS_max_val <- 0
  for(k in 1:n_sim){
    temp_max_val <- max(abs(charts[[k]]$CUSUM["value"]))
    if(temp_max_val >= CUS_max_val){
      CUS_max_val <- temp_max_val
    }
  }
  hseq <- rev(seq(from = h_precision, to = CUS_max_val + h_precision, by = h_precision))

  #Determine control limits using runlength
  control_h <- CUS_max_val
  for(i in seq_along(hseq)){
    #Determine type I error using current h
    typ1err_temp <- sum(sapply(charts, function(x) is.finite(runlength(x, h = hseq[i]))))/n_sim
    if(typ1err_temp <= alpha){
      control_h <- hseq[i]
    } else{
      break
    }
  }

  #When lower-sided, control limit should be negative.
  if(theta < 0){
    control_h <- - control_h
  }


  return(list(call = call,
              charts = charts,
              data = df_temp,
              h = control_h))
}

