% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/bernoulli_control_limit.R
\name{bernoulli_control_limit}
\alias{bernoulli_control_limit}
\title{Determine control limits for the Bernoulli CUSUM by simulation}
\usage{
bernoulli_control_limit(time, alpha = 0.05, followup, psi, n_sim = 200,
  glmmod, baseline_data, theta, p0, p1, h_precision = 0.01, seed = 1041996,
  pb = FALSE, assist)
}
\arguments{
\item{time}{A numeric value over which the type I error \code{alpha} must be restricted.}

\item{alpha}{A proportion between 0 and 1 indicating the required maximal type I error.}

\item{followup}{The value of the follow-up time to be used to determine event time.
Event time will be equal to \code{entrytime + followup} for each subject.}

\item{psi}{A numeric value indicating the estimated Poisson arrival rate of subjects
at their respective units. Can be determined using
\code{\link[success:parameter_assist]{parameter_assist()}}.}

\item{n_sim}{An integer value indicating the amount of units to generate for the
determination of the control limit. Larger values yield more precise control limits,
but increase computation times. Default is 200.}

\item{glmmod}{Generalized linear regression model used for risk-adjustment as produced by
the function \code{\link[stats:glm]{glm()}}. Suggested: \cr
\code{glm(as.formula("(survtime <= followup) & (censorid == 1) ~ covariates"), data = data)}. \cr
Alternatively, a list containing the following elements:
\describe{
\item{\code{formula}:}{a \code{\link[stats:formula]{formula()}} in the form \code{~ covariates};}
\item{\code{coefficients}:}{a named vector specifying risk adjustment coefficients
for covariates. Names must be the same as in \code{formula} and colnames of \code{data}.}
}}

\item{baseline_data}{(optional): A \code{data.frame} used for covariate resampling
with rows representing subjects and at least the
following named columns: \describe{
\item{\code{entrytime}:}{time of entry into study (numeric);}
\item{\code{survtime}:}{time from entry until event (numeric);}
\item{\code{censorid}:}{censoring indicator (0 = right censored, 1 = observed),
(integer).}
} and optionally additional covariates used for risk-adjustment. Can only be specified
in combination with \code{coxphmod}.}

\item{theta}{The \eqn{\theta}{\theta} value used to specify the odds ratio
\eqn{e^\theta}{e^\theta} under the alternative hypothesis.
If \eqn{\theta >= 0}{\theta >= 0}, the chart will try to detect an increase
in hazard ratio (upper one-sided). If \eqn{\theta < 0}{\theta < 0},
the chart will look for a decrease in hazard ratio (lower one-sided).
Note that \deqn{p_1 = \frac{p_0 e^\theta}{1-p_0 +p_0 e^\theta}.}{p1 = (p0 * e^\theta)/(1-p0+p0 * e^\theta).}}

\item{p0}{The baseline failure probability at \code{entrytime + followup} for individuals.}

\item{p1}{The alternative hypothesis failure probability at \code{entrytime + followup} for individuals.}

\item{h_precision}{(optional): A numerical value indicating how precisely the control limit
should be determined. By default, control limits will be determined up to 2 significant digits.}

\item{seed}{(optional): A numeric seed for survival time generation.
Default is 01041996 (my birthday).}

\item{pb}{(optional): A boolean indicating whether a progress bar should
be shown. Default is \code{FALSE}.}

\item{assist}{(optional): Output of the function \code{\link[success:parameter_assist]{parameter_assist()}}}
}
\value{
A list containing three components:
\itemize{
\item \code{call}: the call used to obtain output;
\item \code{charts}: A list of length \code{n_sim} containing the constructed charts;
\item \code{data}: A \code{data.frame} containing the in-control generated data.
\item \code{h}: Determined value of the control limit.
}
}
\description{
This function can be used to determine control limits for the
Bernoulli CUSUM (\code{\link[success]{bernoulli_cusum}}) procedure by
restricting the type I error \code{alpha} of the
procedure over \code{time}.
}
\details{
This function performs 3 steps to determine a suitable control limit.
\itemize{
\item Step 1: Generates \code{n_sim} in-control units (failure rate as baseline).
If \code{data} is provided, subject covariates are resampled from the data set.
\item Step 2: Determines chart values for all simulated units.
\item Step 3: Determines control limits such that at most a proportion \code{alpha}
of all units cross the control limit.
} The generated data as well as the charts are also returned in the output.
}
\examples{
#We consider patient outcomes 100 days after their entry into the study.
followup <- 100

#Determine a risk-adjustment model using a generalized linear model.
#Outcome (failure within 100 days) is regressed on the available covariates:
exprfitber <- as.formula("(survtime <= followup) & (censorid == 1)~ age + sex + BMI")
glmmodber <- glm(exprfitber, data = surgerydat, family = binomial(link = "logit"))

#Determine control limit restricting type I error to 0.1 over 500 days
#using the risk-adjusted glm constructed on the baseline data.
a <- bernoulli_control_limit(time = 500, alpha = 0.1, followup = followup,
 psi = 0.5, n_sim = 10, theta = log(2), glmmod = glmmodber, baseline_data = surgerydat)

print(a$h)
}
\seealso{
\code{\link[success]{bernoulli_cusum}}

Other control limit simulation: 
\code{\link{bk_control_limit}()},
\code{\link{cgr_control_limit}()}
}
\author{
Daniel Gomon
}
\concept{control limit simulation}
