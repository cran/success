#' @title Simulated data set with data of surgery procedures
#' performed at multiple hospitals.
#'
#' @description Data about patients and their surgery procedure from 45 simulated hospitals
#' with patient arrivals in the first 400 days after the start of the study. \cr
#' Patient survival times were determined using a risk-adjusted Cox proportional hazards model
#' with coefficients age = 0.003, BMI = 0.02 and sexmale = 0.2 and exponential baseline hazard rate
#' \eqn{h_0(t, \lambda = 0.01) e^\mu}{h_0(t, \lambda = 0.01) exp(\theta)}.
#' The increase in hazard rate is sampled from a normal distribution for all hospitals:
#' \itemize{
#' \item \eqn{\theta \sim N(log(1), sd = 0.4)}{\theta ~ N(log(1), sd = 0.4)}
#' } This means that the average failure rate of hospitals in the data set
#' should be baseline (\eqn{\theta = 0}{\theta = 0}), with some hospitals
#' experiencing higher and lower failure rates. True failure rate can be found
#' in the column \code{exptheta}. \cr
#' The arrival rate \eqn{\psi}{\psi} of patients at a hospital differs. The arrival rates are:
#' \itemize{
#' \item Hospitals 1-5 & 16-20: 0.5 patients per day (small hospitals)
#' \item Hospitals 6-10 & 21-25: 1 patient per day (medium sized hospitals)
#' \item Hospitals 11-15 & 26-30: 1.5 patients per day (large hospitals)
#' } These are then respectively small, medium and large hospitals.
#'
#'
#'
#' @format A \code{data.frame} with 12010 rows and 9 variables:
#' \describe{
#'   \item{entrytime}{Time of entry of patient into study (numeric)}
#'   \item{survtime}{Time from entry until failure of patient (numeric)}
#'   \item{censorid}{Censoring indicator (0 - right censored, 1 - observed) (integer)}
#'   \item{unit}{Hospital number at which patient received treatment (integer)}
#'   \item{exptheta}{True excess hazard used for generating patient survival (numeric)}
#'   \item{psival}{Poisson arrival rate at hospital which the patient was at (numeric)}
#'   \item{age}{Age of the patient (numeric)}
#'   \item{sex}{Sex of the patient (factor)}
#'   \item{BMI}{Body mass index of the patient (numeric)}
#' }
"surgerydat"
