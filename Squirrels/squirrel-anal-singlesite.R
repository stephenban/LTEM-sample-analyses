# This script will demonstrate how to analyze the Squirrel data collected as 
# part of the LongTerm Ecological Monitoring Initiative
#
# Only one study area can be analyzed with a script. 
#
# This was programmed by Carl James Schwarz, Statistics and Actuarial Science, SFU
# cschwarz@stat.sfu.ca
#
# 2017-02-28 First Edition

# Summary of Protocol
#    Red squirrels regularly emit an audible rattle, 
#    especially when their territories are invaded. 
#    This protocol involves walking a transect (a section of a trail) 
#    and recording the location of rattles heard along the way. 
#
#    Locate as many transects in a given area as possible (up to 5). 
#    Sample them annually but in a different order each year. 
#    Sampling involves walking a defined segment of trail and recording 
#    squirrel rattles or chattering.


# load libraries
library(car)       # for testing for autocorrelation (2 libraries needed - see dwtest)
library(ggfortify) # for residual and other diagnostic plot
library(ggplot2)   # for plotting
library(lmtest)    # for testing for autocorrelation
library(plyr)      # for group processing
library(readxl)    # for opening the Excel spreadsheets and reading off them
library(reshape2)  # for melting and casting
library(lmerTest)  # for the linear mixed modelling
library(stringr)   # string handling (like case conversion)

# Load some common functions
source("../CommonFiles/common.functions.R")


cat("\n\n ***** Squirrel Analysis - Single Site *****  \n\n")

# get the data from the Excel work.books.
# we put the list of work books here, including the file type (xls or xlsx).
# You can put multiple stations here because the station information is included on the raw data

work.books.csv <- textConnection(
"file.name
General Survey-squirrels_PWC_2013.xls
General Survey-squirrels_PWC_2014.xls
General Survey-squirrels_PWC_2015.xls
")

work.books <- read.csv(work.books.csv, as.is=TRUE, strip.white=TRUE, header=TRUE)
cat("File names with the data \n")
work.books


# read the transect and survey information from each workbook and put together into a list
# we need a list here because we need to check (later) that all transects are run on all dates.
# we extract the year from the General survey worksheet and add it to the transect data
squirrel.list <- plyr::dlply(work.books, "file.name", function (x){
    file.name <- file.path("Data", x$file.name)
    transects <- readxl::read_excel(file.name, sheet="Transect Information")
    squirrels <- readxl::read_excel(file.name, sheet="General Survey")
    squirrels$Date  <- as.Date(squirrels$Date, "%d-%b-%y", tz="UTC")
    squirrels$Year  <- as.numeric(format(squirrels$Date, "%Y") )
    transects$Year  <- squirrels$Year[1]
    list(transects=transects, squirrels=squirrels)
})


# paste all of the transect information together and paste all of the general survey information together
transect.df <- plyr::ldply(squirrel.list, function (x){x$transects})
squirrel.df <- plyr::ldply(squirrel.list, function (x){x$squirrels})


#------------ Data Editing -----------
# fix up variable names in the data.frames.
# Variable names in R must start with a letter and contain letters or number or _. 
# Blanks in variable names are not normally allowed. Blanks will be replaced by . (period)
cat("\nOriginal variable names in squirrels data file\n")
names(squirrel.df)

names(squirrel.df) <- make.names(names(squirrel.df))

cat("\nCorrected variable names of data frame\n")
names(squirrel.df)


cat("\nOriginal variable names in transects data frame\n")
names(transect.df)

names(transect.df) <- make.names(names(transect.df))

cat("\nCorrected variable names of transect data frame\n")
names(transect.df)



# Check that the Study Area Name is the same across all years
# Look at the output from the xtabs() to see if there are multiple spellings 
# of the same Study.Area.Name.

# We will convert the Study.Area.Name to Proper Case.
squirrel.df$Study.Area.Name <- stringr::str_to_title(squirrel.df$Study.Area.Name)
xtabs(~Study.Area.Name+Year, data=squirrel.df, exclude=NULL, na.action=na.pass)

transect.df$Study.Area.Name <- stringr::str_to_title(transect.df$Study.Area.Name)
xtabs(~Study.Area.Name+Year, data=transect.df, exclude=NULL, na.action=na.pass)


# Check the dates and year codes to R date format
# Notice that we already converted to R date format for the squirrel.df when we read in the data
xtabs(~Date, data=squirrel.df, exclude=NULL, na.action=na.pass)  # check the date formats. Make sure that all yyyy-mm-dd

xtabs(~Year, data=squirrel.df, exclude=NULL, na.action=na.pass)
xtabs(~Year, data=transect.df, exclude=NULL, na.action=na.pass)


# Check the Transect code to make sure that all the same
# This isn't used anywhere in the analysis but is useful to know
xtabs(~Transect.Label+Year, data=squirrel.df, exclude=NULL, na.action=na.pass)
xtabs(~Transect.Label+Year, data=transect.df, exclude=NULL, na.action=na.pass)


# Check the Species code to make sure that all the same
# This isn't used anywhere in the analysis but is useful to know
xtabs(~Species+Year, data=squirrel.df, exclude=NULL, na.action=na.pass)


# Check the Detection type. We are only interested in CA (calls) - check for upper case everywhere
xtabs(~Detect.Type+Year, data=squirrel.df, exclude=NULL, na.action=na.pass)
squirrel.df <- squirrel.df[ squirrel.df$Detect.Type == "CA",]  # select only calls
xtabs(~Detect.Type+Year, data=squirrel.df, exclude=NULL, na.action=na.pass)


# Summarize the total number of calls to the Year-Date-Transect level
count.transect <- plyr::ddply(squirrel.df, c("Study.Area.Name","Year","Date","Transect.Label"), 
                              plyr::summarize, n.calls=length(Date))
xtabs(~n.calls+Year, data=count.transect)  # Notice that no 0's are present


# Impute 0 values. Create a list of all transect x dates for each year of the study
unique.transect <- unique(transect.df[,c("Study.Area.Name","Year","Transect.Label")])
unique.date     <- unique(squirrel.df[,c("Study.Area.Name","Year","Date")])

# create the combination of transects and dates for Study-area year combination
transect.date.set <- plyr::ddply(unique.transect, c("Study.Area.Name","Year"), function(x, unique.date){
    # Extract the dates for this study area - year combination
    dates <- unique.date[ x$Study.Area.Name[1] == unique.date$Study.Area.Name & 
                          x$Year[1]            == unique.date$Year, "Date" ]
    transect.date <- expand.grid(Transect.Label=x$Transect.Label,
                                 Date          =dates, stringsAsFactors=FALSE)
    transect.date$Study.Area.Name <- x$Study.Area.Name[1]
    transect.date
}, unique.date=unique.date)
head(transect.date.set)

# match up the expanded set with the actual data. Missing values will be generate which will
# be converted to zero
dim(count.transect)
count.transect <- merge(count.transect, transect.date.set, all=TRUE)
dim(count.transect)

# which date/transect combinations were missing
cat("Missing transect data on the following date --- check your data\n")
count.transect[ is.na(count.transect$n.calls),]

# Impute a value of 0 for the total calls
count.transect$n.calls[ is.na(count.transect$n.calls)] <- 0
count.transect[ is.na(count.transect$n.calls),]

# finally summary table
xtabs(n.calls~Transect.Label+Date+Study.Area.Name, data=count.transect, exclude=NULL, na.action=na.pass)
xtabs(~Transect.Label+Date+Study.Area.Name, data=count.transect, exclude=NULL, na.action=na.pass)

# Summarize the imputed data to one number per year per transect
count.transect <- plyr::ddply(count.transect, c("Study.Area.Name","Year","Transect.Label"), 
                              plyr::summarize, n.calls=mean(n.calls))
count.transect

# Get the file prefix
file.prefix <- make.names(count.transect$Study.Area.Name[1])
file.prefix <- gsub(".", '-', file.prefix, fixed=TRUE) # convert . to -
file.prefix <- file.path("Plots",file.prefix)

#----------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------
#  Analysis of the number of calls over time.

# Make a preliminary plot

prelim.plot <- ggplot(data=count.transect, aes(x=Year, y=log(n.calls), color=Transect.Label, shape=Transect.Label))+
   ggtitle("Squirrel count data")+
   ylab("log(Mean count)")+
   geom_point(position=position_dodge(width=.1))+
   geom_line( position=position_dodge(width=.1))+
   facet_wrap(~Study.Area.Name, ncol=1)+
   scale_x_continuous(breaks=min(count.transect$Year,na.rm=TRUE):max(count.transect$Year,na.rm=TRUE))
prelim.plot 
ggsave(plot=prelim.plot, 
       file=paste(file.prefix,'-plot-prelim.png', sep=""),
       h=4, w=6, units="in",dpi=300)


# This is a regression analysis with Year as the trend variable.
# We need to account for the same transect being measured over time and year process error..

count.transect$YearF           <- factor(count.transect$Year)
count.transect$Transect.LabelF <- factor(count.transect$Transect.Label)
count.fit.lmer <- lmerTest::lmer(log(n.calls) ~ Year + (1|Transect.LabelF) + (1|YearF), data=count.transect)
anova(count.fit.lmer, ddf="kenward-roger")
summary(count.fit.lmer)
VarCorr(count.fit.lmer)



# Look at the residual plots and save them to the directory
diag.plot <- sf.autoplot.lmer(count.fit.lmer)  # residual and other diagnostic plots
plot(diag.plot)
ggsave(plot=diag.plot, 
       file=paste(file.prefix,"-count-residual-plot.png",sep=""),
       h=6, w=6, units="in", dpi=300)


# check for autocorreclation 
count.transect$resid <- log(count.transect$n.calls) - predict(count.fit.lmer, newdata=count.transect, re.form=~0)
mean.resid <- plyr::ddply(count.transect, "Year", summarize, mean.resid=mean(resid))
resid.fit <- lm( mean.resid ~ 1, data=mean.resid)
dwres1 <- car::durbinWatsonTest(resid.fit)
dwres1
dwres2 <- lmtest::dwtest(resid.fit)
dwres2


# extract a table of the slopes
count.slopes <- data.frame(
       Study.Area.Name = count.transect$Study.Area.Name[1],
       slope           = fixef(count.fit.lmer)["Year"],
       slope.se        = summary(count.fit.lmer)$coefficients["Year","Pr(>|t|)"],
       p.value         = summary(count.fit.lmer)$coefficients[row.names(summary(count.fit.lmer)$coefficients)=="Year"  ,"Pr(>|t|)"], 
       #r2             = summary(count.fit.lmer)$r.squared,  # not defined for mixed effect models
       stringsAsFactors=FALSE)
count.slopes


# compute the fitted values from the model
# The model was run on the log(average count), so we need to back transform
count.fitted <- data.frame(
                 Study.Area.Name=count.transect$Study.Area.Name[1],
                 Year=seq(min(count.transect$Year, na.rm=TRUE),max(count.transect$Year, na.rm=TRUE), .1),
                 stringsAsFactors=FALSE)
count.fitted$pred.mean <- exp(predict(count.fit.lmer, newdata=count.fitted,type="response", re.form=~0))
head(count.fitted)


# Make the summary plot with the estimated slope and fitted line
count.plot.summary <- ggplot2::ggplot(data=count.transect,
                                    aes(x=Year, y=n.calls))+
   ggtitle("Squirrel count ")+
   ylab("Squirrel Count")+
   geom_point(size=3, aes(color=Transect.Label))+
   geom_line(data=count.fitted, aes(y=pred.mean))+
   facet_wrap(~Study.Area.Name, ncol=1, scales="free" )+
   scale_x_continuous(breaks=min(count.transect$Year,na.rm=TRUE):max(count.transect$Year,na.rm=TRUE))+
   geom_text(data=count.slopes, aes(x=min(count.transect$Year, na.rm=TRUE), y=max(count.transect$n.calls, na.rm=TRUE)), 
             label=paste("Slope (on log scale) : ",round(count.slopes$slope,2), 
                         " ( SE "  ,round(count.slopes$slope.se,2),")",
                         " p :"    ,round(count.slopes$p.value,3)),
                         hjust="left")
count.plot.summary
ggsave(plot=count.plot.summary, 
       file=paste(file.prefix,'-count-plot-summary.png',sep=""),
       h=6, w=6, units="in", dpi=300)




##### if the lmer() function does not countge, you can repeat the analysis on the average of all the transect

# Compute the average total count for each transect so I can plot these over time
count.avg <- plyr::ddply(count.transect, c("Study.Area.Name","Year"), plyr::summarize,
                          count=mean(n.calls, na.rm=TRUE))
count.avg

# Make a preliminary plot of average count by years

prelim.count.plot.avg <- ggplot(data=count.avg, aes(x=Year, y=log(count)))+
   ggtitle("log(Mean count) - averaged over all transects in a year")+
   ylab("log(Mean count) on the plots")+
   geom_point(position=position_dodge(width=.2))+
   geom_smooth(method="lm", se=FALSE)+
   scale_x_continuous(breaks=min(count.avg$Year, na.rm=TRUE):max(count.avg$Year, na.rm=TRUE))+
   facet_wrap(~Study.Area.Name, ncol=1)
prelim.count.plot.avg 
ggsave(plot=prelim.count.plot.avg, 
       file=paste(file.prefix,'-count-plot-prelim-avg.png',sep=""),
       h=6, w=6, units="in",dpi=300)


# This is a simple regression analysis with Year as the trend variable 

count.fit.avg <-  lm(log(count) ~ Year, data=count.avg)
anova(count.fit.avg)
summary(count.fit.avg)

# Look at the residual plot 
diag.plot <- autoplot(count.fit.avg)  # residual and other diagnostic plots
show(diag.plot)
ggplot2::ggsave(plot=diag.plot, 
                file=paste(file.prefix,"-count-residual-avg-plot.png",sep=""),
                h=6, w=6, units="in", dpi=300)

# check for autocorrelation - look at the average residual over time
count.avg$resid <- log(count.avg$count) - predict(count.fit.avg, newdata=count.avg)
mean.resid <- plyr::ddply(count.avg, "Year", summarize, mean.resid=mean(resid))
resid.fit <- lm( mean.resid ~ 1, data=mean.resid)
dwres1 <- car::durbinWatsonTest(resid.fit)
dwres1
dwres2 <- lmtest::dwtest(resid.fit)
dwres2


# extract the slope
count.slopes.avg <- data.frame(
       Study.Area.Name =count.transect$Study.Area.Name[1],
       slope           = coef(count.fit.avg)["Year"],
       slope.se        = summary(count.fit.avg)$coefficients["Year","Pr(>|t|)"],
       p.value         = summary(count.fit.avg)$coefficients[row.names(summary(count.fit.avg)$coefficients)=="Year"  ,"Pr(>|t|)"], 
       r2              = summary(count.fit.avg)$r.squared, 
       stringsAsFactors=FALSE)
count.slopes.avg


# compute the fitted values from the model
count.fitted.avg <- data.frame(
                 Study.Area.Name=count.transect$Study.Area.Name[1],
                 Year=seq(min(count.avg$Year, na.rm=TRUE),max(count.avg$Year, na.rm=TRUE), .1),
                 stringsAsFactors=FALSE)
# because we fit on the log-scale, we need to antilog the predictions
count.fitted.avg$pred.mean <- exp(predict(count.fit.avg, newdata=count.fitted,type="response"))
head(count.fitted.avg)

# Plot with trend line 
count.plot.summary.avg <- ggplot2::ggplot(data=count.avg,
                                    aes(x=Year, y=count))+
   ggtitle("Total Species count")+
   ylab("Mean Total % count")+
   geom_point(size=3,position=position_dodge(w=0.2))+
   geom_line(data=count.fitted.avg, aes(x=Year,y=pred.mean))+
   facet_wrap(~Study.Area.Name, ncol=1, scales="free" )+
   scale_x_continuous(breaks=min(count.avg$Year, na.rm=TRUE):max(count.avg$Year,na.rm=TRUE))+
   geom_text(data=count.slopes.avg, aes(x=min(count.avg$Year, na.rm=TRUE), y=max(count.avg$count, na.rm=TRUE)), 
             label=paste("Slope : ",round(count.slopes.avg$slope,2), 
                         " ( SE "  ,round(count.slopes.avg$slope.se,2),")",
                         " p :"    ,round(count.slopes.avg$p.value,3)),
                         hjust="left")
count.plot.summary.avg
ggsave(plot=count.plot.summary.avg, 
       file=paste(file.prefix,'-count-plot-summary-avg.png',sep=""),
       h=6, w=6, units="in", dpi=300)




