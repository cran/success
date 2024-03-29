#' Continuous time Generalized Rapid response CUSUM (CGR-CUSUM) helper - matrix
#' formulation of the problem - version 2
#'
#' @description This function calculates the value of the CGR-CUSUM using a
#' matrix formulation of the problem - this can require a lot of available RAM.
#'
#' @inheritParams cgr_cusum
#' @param data \code{data.frame} containing the following named columns:
#' \itemize{
#' \item \code{entrytime} numeric - time of entry into study,
#' \item \code{otime} numeric - time from entry until event,
#' \item \code{censorid} integer - (optional) censoring indicator (0 = right censored, 1 = observed),
#\item \code{cause} factor - cause of event - competing risks.
#' } and optionally additional covariates used for risk-adjustment.
#' @param displaypb boolean Display a progress bar?
#'
#' @return A matrix with 4 named columns:
#' \itemize{
#'   \item $time time at which the value of the CGR-CUSUM was determined
#'   \item $value value at corresponding time of the CGR-CUSUM
#'   \item $exp_theta_t value at corresponding time of the MLE \eqn{\hat{\theta}_t}{\theta_t}
#'   \item $S_nu time from which individuals contribute to the chart \eqn{S_\nu}{S_\nu}
#' }
#'
#' @importFrom utils txtProgressBar
#' @importFrom utils setTxtProgressBar
#' @importFrom parallel detectCores
#' @importFrom parallel stopCluster
#' @importFrom parallel parSapply
#' @importFrom parallel makeCluster
#' @importFrom pbapply pbmapply
#' @importFrom pbapply pbsapply
#' @importFrom pbapply pbapply
#' @importFrom parallel clusterExport
#' @importFrom pbapply pboptions
#' @importFrom Rfast binary_search
#'
#' @noRd
#' @keywords internal
#'
#' @author Daniel Gomon
#'
#'
#' @examples
#' \donttest{
#' require(survival)
#' tdat <- subset(surgerydat, hosp_num == 1)
#' tdat$otime <- tdat$entrytime + tdat$survtime
#' tcbaseh <- function(t) chaz_exp(t, lambda = 0.01)
#' varsanalysis <- c("age", "sex", "BMI")
#' exprfit <- as.formula(paste("Surv(survtime, censorid) ~" ,paste(varsanalysis, collapse='+')))
#' tcoxmod <- coxph(exprfit, data= surgerydat)
#' #Alternatively, cbaseh can be left empty when specifying coxphmod through coxph()
#' cgr2 <- cgr_helper_mat_2(data = tdat, ctimes = unique(tdat$entrytime + tdat$survtime),
#'                          coxphmod = tcoxmod, cbaseh = tcbaseh, displaypb = TRUE)
#' }

cgr_helper_mat <- function(data, ctimes, h, coxphmod, cbaseh, ncores, displaypb = FALSE, dependencies,
                           maxtheta){

  #!
  #ACTIVE VERSION
  #!
  #This function consists of the following functions:
  #maxoverk: calculate CGI value at specific ctime, considering only patients with entrytime S_i >= k
  #maxoverj: Calculate CGR value at specific ctime by applying maxoverk on all relevant starting times (helperstimes)
  #fin = apply maxoverj to all required construction times to determine the values of CGR(t) for all ctimes
  #TRIPLE APPLY CONSTRUCTION.

  #Lambdamat is determined using an mapply on the columns of a matrix which is structured as:
  #      ctime_1  ctime_2 ctime_3  ctime_4 ................ ctime_p
  # i=1 (                                                            )
  # i=2 (     accumulated hazard of subject 2 at time in column      )
  # i=3 (                           subject 3                        )
  # ... (                             ...                            )
  # i=p (                                                            )
  #
  # Then we determine all patients which are relevant for constructing at a certain timepoint
  # by indexing over the data (checking their Stimes) and determine their active
  # contribution by summing over the column at the desired ctime.
  # The number of failures at that timepoint is determined the same way
  ctimes <- ctimes[which(ctimes >= min(data$entrytime))]

  data_mat <- as.matrix(data[, c("censorid", "entrytime", "otime")])
  data_mat[, "entrytime"] <- as.double(data_mat[, "entrytime"])
  if (!identical(FALSE, is.unsorted(data_mat[, "entrytime"]))){
    stop("'data$entrytime' must be sorted non-decreasingly and not contain NAs.")
  }


  #Remove R check warnings
  entrytime <- NULL

  if(ncores > 1){
    #Create a cluster for parallel computing and error check
    real_cores <- detectCores()
    if(ncores > real_cores){
      warning(paste0("More cores requested (", ncores ,") than detected (", real_cores,") by R. \n Proceed at own risk."))
    }
    cl <- makeCluster(ncores)
  } else{
    cl <- NULL
  }

  #Calculate Lambda_i for a single person at times - can be applied to matrix columns
  Lambdafun_noparallel <- function(entrytime, otime, times, cbaseh){
    lamval <- sapply(times, FUN = function(x) {
      if(x >= entrytime){
        cbaseh(min(x, otime) - entrytime)
      } else{0}
    })
  }
  #Same as lamdafun_noparallel, but can be applied to matrix rows using apply
  Lambdafun <- function(y, times, cbaseh){
   lamval <- sapply(times, FUN = function(x) {
     if(x >= y[1]){
       cbaseh(min(x, y[2]) - y[1])
     } else{0}
   })
  }

  #---------NEW FCT BODY-------------
  #Calculate subject specific failure risk (exp(\beta Z))
  riskdat <- calc_risk(data, coxphmod)
  #ctimes are already pre-sorted in cgrcusum
  #Create matrix containing Lambda_i(t) per patient. Rows represent patient i
  if(displaypb){
    message("Step 1/2: Determining hazard contributions.")
    pboptions(type = "timer")
  } else{
    pboptions(type = "none")
  }


  #MULTI-CORE:
  #Provide dependencies to cluster (such as functions required for clusters)
  if(!missing(dependencies) & ncores > 1){
    clusterExport(cl, dependencies, envir=environment())
  }
  #Create matrix containing Lambda_i(t) per patient. Rows represent subject i, columns represent ctimes
  #the columns are exactly ctimes
  #tryCatch: if MULTI-CORE doesn't work, go back to SINGLE-CORE
  lambdamat <- tryCatch({t(pbapply(X = data[, c("entrytime", "otime")], MARGIN = 1,
                                  FUN = Lambdafun, times = ctimes, cbaseh = cbaseh, cl = cl))},
           error = function(cond){
             asd <- cond
             message(cond)
             message(paste0("\nPlease specify above missing functions/variables as a list to cgr_cusum under"
                     ," the argument 'dependencies'"))
             message("\nStep 1/2 will continue WITHOUT PARALLELIZATION - MAY BE SLOW!")
             t(pbmapply(FUN = Lambdafun_noparallel, entrytime = data$entrytime,
                                     otime = data$otime, MoreArgs = list( times = ctimes, cbaseh = cbaseh)))
           }
           )


  #Risk-adjust the cumulative intensity calculated at times
  lambdamat <- lambdamat * as.vector(riskdat)


  #Determine times from which to construct the CGR
  helperstimes <- as.double(sort(unique(data$entrytime)))
  #THIS DOESNT WORK YET WHEN YOU HAVE INSTANT FAILURES
  #BECAUSE THEN YOU CANT DETERMINE THETA - INSTANT FAILURE -> theta = Inf, so
  #you ignore instant failure and instead look at previous closest failure time
  #But if you use helperfailtimes, you don't look back and instead you get
  #a 0 value (see dat2 test in LROIpkgtest)
  helperfailtimes <- numeric(length(helperstimes))
  #Determine failure times, as we only have to use helperstimes with failure times
  #smaller than the construction time.
  for(i in seq_along(helperstimes)){
    #smallest EVENT time for given entry time
    failtemptime <- min(subset(data, entrytime == helperstimes[i])$otime)
    #Assign smallest fail time to vector
    helperfailtimes[i] <- failtemptime
    #If EVENT time equals entry time, equate previous failtime to this one.
    #This way, the previous observation will be considered for calculating the chart.
    if(failtemptime == helperstimes[i]){
      if(i > 1){
        helperfailtimes[i-1] <- failtemptime
      }
    }
  }


  #Function used for maximizing over starting points (patients with starting time >= k)
  maxoverk <- function(helperstime, ctime, ctimes, data, lambdamat, maxtheta){
    #Determine part of data that is active at required times
    lower <- binary_search(data[, "entrytime"], helperstime, index = TRUE)
    upper <- nrow(data) - binary_search(rev(-1*data[, "entrytime"]), (-1*ctime), index = TRUE) +1

    ########This part of the code can be improved to reduce comp time#######
    #This code works because data is sorted according to entrytime and then otime
    #We use findInterval instead of match or which because it's faster
    #lower <- .Internal(findInterval(data[, "entrytime"], helperstime, rightmost.closed = FALSE,
    #                                all.inside = FALSE, left.open = TRUE)) + 1
    #upper <- .Internal(findInterval(data[, "entrytime"], ctime, rightmost.closed = FALSE,
    #                                all.inside = FALSE, left.open = FALSE))
    ########This part of the code can be improved to reduce comp time#######
    #findInterval is faster than binary_search, but we may not use
    #.Internal functions in R packages
    #If we remove .Internal, then an is.sorted() check is executed every time,
    #greatly increasing the required computation time.

    matsub <- lower:upper
    #Above code used to be:
    #matsub <- which(data[, "entrytime"] >= helperstime & data[, "entrytime"] <= ctime)
    #This was slow, so use Rfast functions instead, .Internal functions a bit faster, rewrite in Rcpp in future.

    #The cumulative intensity at that time is the column sum of the specified ctime
    AT <- sum(lambdamat[matsub, match(ctime, ctimes)])

    #Subset only the part of data where patients arriving after helperstime and having
    #otime before ctime are considered
    tmat <- data[matsub, , drop = FALSE]

    #Determine amount of failures before and at ctime.
    #Maybe do sum( < ctimes) and sum( == ctime) and then calculate NDT <- sum(both)
    NDT <- sum(tmat[, "censorid"] == 1 & tmat[, "otime"] <= ctime)
    NDT_current <- sum(tmat[, "censorid"] == 1 & tmat[, "otime"] == ctime)

    #Old and slow version:
    #NDT <- length(which(data[matsub, ]$censorid == 1 & data[matsub,]$otime <= ctime))
    #NDT_current <- length(which(data[matsub, ]$censorid == 1 & data[matsub, ]$otime == ctime))

    #Determine MLE of theta
    thetat <- log(NDT/AT)
    thetat_down <- log((NDT-NDT_current)/AT)
    if (is.finite(thetat)){
      thetat <- min(max(0, thetat), abs(maxtheta))
    } else {thetat <- 0}
    if (is.finite(thetat_down)){
      thetat_down <- min(max(0, thetat_down), abs(maxtheta))
    } else {thetat_down <- 0}
    #Determine value of CGI-CUSUM using only patients with S_i > helperstimes[i]
    CGIvalue <- thetat* NDT - (exp(thetat)- 1) * AT
    CGI_down <- thetat_down * (NDT - NDT_current) - (exp(thetat_down)- 1) * AT
    #Return both the value of CGI and the MLE (to be used later)
    return(c(CGIvalue, CGI_down, thetat, thetat_down))
  }

  #Function to calculate CGR value at one ctime by ways of maximizing over all CGI(t) values.
  #Achieved by applying the maxoverk function and determining maxima.
  maxoverj <- function(y){
    #Determine which helperstimes to use in this iteration.
    temphelperstimes <- helperstimes[which(helperstimes <= y & helperfailtimes <= y)]
    #Problem is that temphelperstimes is sometimes empty (integer(0)), which
    #causes .findInterval in maxoverk to not work.
    a <- sapply(temphelperstimes,
                function(x) maxoverk(helperstime = x,  ctime = y, ctimes = ctimes,
                                     data = data_mat,
                                     lambdamat = lambdamat, maxtheta = maxtheta))
    #We first apply the maxoverk function to determine CGI values
    #starting from all relevant helper S_i times (patient entry times)
    #We only need to calculate the CGI value when the the starting time of patients
    #a <- sapply(helperstimes[which(helperstimes <= y)],
    #            function(x) maxoverk(helperstime = x,  ctime = y, ctimes = ctimes, data = data, lambdamat = lambdamat))
    #If there are no values to be calculated, return trivial values
    if(length(a) == 0){
      return(c(0,0,0,0,1,1))
    }else{
      #First row is value of chart, second row associated value of theta
      #Determine which entry is the largest (largest CGI value)
      tidmax <- which.max(a[1,])
      #Determine which entry is largest when not considering current failures.
      tidmin <- which.max(a[2,])
      #Determine the corresponding value of CGI(t)
      atemp <- a[, tidmax]
      #And the corresponding lower value of CGI(t)
      atemp_down <- a[, tidmin]
      #Returns c(chartval, thetaval, maxindex) at maximum of CGI(t)
      #More specific: CGI_up, CGI_down, theta_up, theta_down, idx_up, idx_down (see maxoverk())
      return(c(atemp[1], atemp_down[2], atemp[3], atemp_down[4], temphelperstimes[tidmax], temphelperstimes[tidmin]))
    }
  }

  maxoverj_h <- function(y, h){
    #We first apply the maxoverk function to determine CGI values
    #starting from all relevant helper S_i times (patient entry times)
    #We only need to calculate the CGI value when the the starting time of patients
    #is before our construction time
    #For when I fix helperfailtimes problem.
    temphelperstimes <- helperstimes[which(helperstimes <= y & helperfailtimes <= y)]
    a <- sapply(temphelperstimes,
                function(x) maxoverk(helperstime = x,  ctime = y, ctimes = ctimes,
                                     data = data_mat,
                                     lambdamat = lambdamat, maxtheta = maxtheta))
    #a <- sapply(helperstimes[which(helperstimes <= y)],
    #            function(x) maxoverk(helperstime = x,  ctime = y, ctimes = ctimes, data = data, lambdamat = lambdamat))

    if(length(a) == 0){
      return(c(0,0,0,0,1,1))
    }else{
      #First row is value of chart, second row associated value of theta
      #Determine which entry is the largest (largest CGI value)
      tidmax <- which.max(a[1,])
      #Determine which entry is largest when not considering current failures.
      tidmin <- which.max(a[2,])
      #Determine the corresponding value of CGI(t)
      atemp <- a[,tidmax]
      #And the corresponding lower value of CGI(t)
      atemp_down <- a[, tidmin]
      if(abs(atemp[1]) >= abs(h)){
        hcheck <<- TRUE
        stopind <<- TRUE
        stopctime <<- match(y, ctimes)
      }
      #Returns c(chartval, thetaval) at maximum of CGI(t)
      #More specific: CGI_up, CGI_down, theta_up, theta_down, idx_up, idx_down (see maxoverk())
      return(c(atemp[1], atemp_down[2], atemp[3], atemp_down[4], temphelperstimes[tidmax], temphelperstimes[tidmin]))
    }
  }

  #hcheck used to check whether value of CGR has surpassed control limit
  hcheck <- FALSE
  stopind <- FALSE
  stopctime <- NA

  #Calculate maxoverk for every construction time ctimes
  #If progress bar, then pbsapply (with possible multi-core)
  if(displaypb){
    message("Step 2/2: Determining chart values.")
  }
  if(!missing(h)){
    #Calculate maxoverk for every construction time ctimes by applying maxoverj on all ctimes.
    if(ncores > 1){
      stopCluster(cl)
      cl <- NULL
    }
    fin <- pbsapply(ctimes, function(x){ if(isFALSE(hcheck)){ maxoverj_h(x, h = h)} else{return(c(0,0,0,0,1,1))}}, cl = cl)
  } else{
    fin <- pbsapply(ctimes, maxoverj, cl = cl)
    if(ncores > 1){
      stopCluster(cl)
    }
  }
  Gt <- t(fin)
  if(!is.na(stopctime)){
    Gt <- Gt[1:stopctime,]
  }
  Gt[,3] <- exp(Gt[,3])
  Gt[,4] <- exp(Gt[,4])
  #No longer necessary, provide start time directly
  #Gt[,5] <- helperstimes[Gt[,5]]
  #Gt[,6] <- helperstimes[Gt[,6]]
  if(!is.na(stopctime)){
    Gt <- cbind(ctimes[1:stopctime], Gt)
  } else{
    Gt <- cbind(ctimes, Gt)
  }
  Gt <- unname(Gt)

  #Initiate final matrix
  Gt_final <- matrix(c(min(ctimes, min(data$entrytime)), 0, 1, 0), ncol = 4)
  for(l in 1:nrow(Gt)){
    if(Gt[l, 2] == Gt[l,3]){
      Gt_final <- rbind(Gt_final, Gt[l, c(1, 2, 4, 6)])
    } else{
      Gt_final <- rbind(Gt_final, Gt[l, c(1, 3, 5, 7)])
      Gt_final <- rbind(Gt_final, Gt[l, c(1, 2, 4, 6)])
    }
  }
  Gt_final <- as.data.frame(Gt_final)

  colnames(Gt_final) <- c("time", "value", "exp_theta_t", "S_nu")



  #return list of relevant values
  return(Gt_final)
}
