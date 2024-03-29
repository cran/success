% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/cgr_summary.R
\name{summary.funnelplot}
\alias{summary.funnelplot}
\title{Summarizes S3 objects in this package.}
\usage{
\method{summary}{funnelplot}(object, ...)
}
\arguments{
\item{object}{S3 object to summarize}

\item{...}{extra parameters}
}
\value{
A \code{data.frame} with:
\itemize{
\item \code{unit}: unit number/identifier;
\item \code{observed}: the observed amount of failures at respective unit;
\item \code{expected}: the expected amount of failures at respective unit,
given that the unit is performing at target;
\item \code{numtotal}: total number of subjects at respective unit;
\item \code{p}: estimated probability of failure at unit;
\item \code{'0.xx'}: better/normal/worse proportion of failure at specified
confidence levels.
}
}
\description{
Prints a summary of the
\code{funnelplot} object.
}
\section{Methods (by class)}{
\itemize{
\item \code{summary(funnelplot)}: summarize instances detected by the
\code{funnelplot} object

}}
\seealso{
\code{\link[success:funnel_plot]{funnel_plot}}
}
