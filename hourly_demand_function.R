

#load libraries
library(tidyverse)
library(dplyr)
library(RColorBrewer)
library(lubridate)

#LOAD DATA
#Price Schedule
price_schedule <- read_csv("Model_Map/2018_Summer_TOU_EV_4.csv")

#Price Schedule Options (All in Model_Map Folder)

#2018 Summer 3
read_csv("Model_Map/2018_Summer_TOU_EV_3.csv")

#2018 Summer 4
read_csv("Model_Map/2018_Summer_TOU_EV_4.csv")

#2018 Winter 3
read_csv("Model_Map/2018_Winter_TOU_EV_3.csv")

#2018 Winter 4
read_csv("Model_Map/2018_Winter_TOU_EV_4.csv")

#2018 Winter D
read_csv("Model_Map/2018_Winter_TOU_EV_D.csv")

#2019 Summer 8
read_csv("Model_Map/2019_Summer_TOU_EV_8.csv")

#2019 Winter 8
read_csv("Model_Map/2019_Winter_TOU_EV_8.csv")


#Baseline Usage
#baseline <- read_csv("Model_Map/03-18_WP_Avg.csv")

DC_baseline <- read_csv("Model_Map/DC_Avg_Usage.csv")
WP_baseline <- read_csv("Model_Map/Workplace_Avg_Usage.csv")
MUD_baseline <- read_csv("Model_Map/MUD_Avg_Usage.csv")
F_baseline <- read_csv("Model_Map/Fleet_Avg_Usage.csv")


baseline <- bind_rows("Destination Center" = DC_baseline, "Fleet" = F_baseline, "Multi Unit Dwelling" = MUD_baseline,"Workplace" = WP_baseline, .id = "Segment") 
#View(baseline)

Wokplace_Total_Usage <- read_csv("Model_Map/Wokplace_Total_Usage.csv")
Workplace_Avg_Usage <- read_csv("Model_Map/Workplace_Avg_Usage.csv")



Workplace_Daily_Usage <- read_csv("Workplace_Daily_Usage.csv")
Workplace_Daily_Usage$Date <- as.Date(Workplace_Daily_Usage$Date, "%m/%d/%Y")
Workplace_Daily_Usage <- Workplace_Daily_Usage %>% 
  mutate(weekday = wday(Date, label=TRUE), month = month(Date,label = TRUE), Year = year(Date)) #add columns to the end of sheet to identify day of week, month, year
#as a check for the chunk below




Workplace_Weekday_Usage <- Workplace_Daily_Usage %>% 
  filter(!wday(Date) %in% c(1, 7) & month(Date) == 11 & year(Date) == 2018 )#keep everything that's nopt sunday(1) and satuday(7)


Workplace_Weekday_Average <- apply(select(Workplace_Weekday_Usage, '1':'24'),2,mean) 



# Number of Chargers by Segment
#chargers <- read_csv("Model_Map/Chargers_Installed_03-18.csv")
Chargers <- read_csv("Model_Map/Chargers.csv")
Event_Chargers <- read_csv("Model_Map/Event_Chargers.csv")

add_baseline_chargers <- Chargers %>% 
  filter(Market_Segment!= "Total") %>% 
  slice(rep(1:n(),each=24))

#WHY REPEAT 24 TIMES?? time doesnt matter here

#Event Usage
DC_Event_Total_Usage <- read_csv("Model_Map/DC_Event_Total_Usage.csv")
Workplace_Event_Total_Usage <- read_csv("Model_Map/Workplace_Event_Total_Usage.csv")

#Elasticities with format 9X3 with columns Base_Hr, Changed_Hr, and Elasticity
#Changed_Hr is the Hour where the price change occurs, Base_Hr is the hour in which demand changes
Elasticities <- read_csv("SDGE_Elasticities.csv")
SDGE_P_SOP_Ratios <- read_csv("SDGE_P_SOP_Ratios.csv")


#Ratio for selecting Default Elasticities
P_SOP_Ratio <- max(price_schedule$P0)/min(price_schedule$P0)
#Matches our closest Ratio to Inputted Ratio
closest_schedule <- SDGE_P_SOP_Ratios$Rate_Schedule[which.min(abs(SDGE_P_SOP_Ratios$P_SOP_Ratio - P_SOP_Ratio))]
closest_elasticities <- match(closest_schedule, names(Elasticities))
#Uses Elasticities of rate schedule with closest ratio



p_c <- -0.05 #price change
i_h <- c(12:15) #intervention hours
t_a <- 0 #throttling amount
t_h <- c(7:11) #throttling hours
sch <- closest_elasticities #elasticities to use for price intervention (column in the elasticities dataframe) -  Non PV Summer Weekday EPEV L. The default now picks from the ratio 
sg <- "Workplace" #segment
mth <- "Mar_18" #month
pwr <- 6.6 #charger power
pk <- c(17:21) #target window to shift out off (this is only used in the output calculations below, not for the function)
int_ch <- filter(Chargers, Market_Segment == sg) %>% 
  select(mth) %>% 
  as.numeric() # default is to MARCH 2018
int_e_b <- TRUE
i_c_e <- 1






hourly_demand <- function(segment = sg, 
                          month = mth, 
                          charger_power = pwr,
                          schedule = sch,
                          price_change = p_c,
                          intervention_hours = i_h, 
                          intervention_chargers = int_ch,#if intervention_chargers is                           ever changed, have to also set int_equals_baseline = FALSE
                          int_equals_baseline = int_e_b, 
                          throttle_amount = t_a,
                          throttle_hours = t_h, 
                          intervention_comm_effect = i_c_e){
  
  library(tidyverse)
  library(lubridate)
  
  #CONTEXT#####
  
  #This section puts the Hr, initial price (P0), period, initial unscaled load (Xi), and scaled load (XO) into EV_Demand
  
  #Price Schedule is read in above
  
  # Elasticity 
  chosen_elasticities <- Elasticities[c(1,2,schedule)] #this pulls out columns 1, 2, and the designated elasticity (from row 74 into a new dataframe) 
  colnames(chosen_elasticities) <- c("Base_Hr","Changed_Hr","Elasticity")
  
  
  #price_schedule$period <- factor(price_schedule$period, levels = c("P","MP","OP"))
  
  #Baseline
  
  #filter the number of chargers by market segment and month, change to numeric (have to set the month and segment otherwise it will take the default, workplace and March 2018)
  baseline_chargers <-filter(Chargers, Market_Segment == segment) %>% 
    select(month) %>% 
    as.numeric()
  
  
  intervention_chargers <- ifelse(int_equals_baseline == TRUE, baseline_chargers, intervention_chargers)
  
  #WP_Chargers <- chargers$Workplace #Number of Chargers (C)
  #DC_Chargers <- chargers$Workplace #Number of Chargers (C)
  baseline_month<- baseline %>% 
    filter(Segment == segment) %>% 
    select(month) %>%
    unlist()
  
  
  EV_Demand <- mutate(price_schedule, I01 = 0 ,Xi = baseline_month, X0 = baseline_month/baseline_chargers*intervention_chargers) #340 here comes from the number of chargers installed for the baseline. I01 refers to the hours where there is an intervention. 
  
  EV_Demand$I01[intervention_hours] <-1
  
  
  #MAX_THEORETICAL#### 
  #Theoretical max is based on the current number of chargers in the SCE Charge Ready pilot program, multiplied by the average power rating of Level 2 EV chargers (6.6 kW), multiplied by 1 hour.  This gives us the total number of kWh for each hour that could be achieved if every charger were utilized during the target load shift window of 11 AM - 3 PM.
  
  
  Max_Theory <- intervention_chargers*charger_power
  
  
  ####
  
  
  
  #SPLINING####
  x <- c(1:24) #used for the 24 hours in for loops (24 elasticity columns)
  
  
  #This makes a table for each hour that lists the midpoint hours that will be splined, hours as <24, rate period, and elasticity relative to the hour.
  
  
  #Finds the hours in the rate schedule just before the period changes
  change_points <- which(price_schedule$Period != dplyr::lag(price_schedule$Period)) - 1
  
  #Finds the midpoints of each "chunk" of rate periods unless the "chunk" spans over the end of the day
  mid_points <- change_points[-length(change_points)] +diff(change_points)/2
  
  #finds the midpoint of the "chunk" of rate period that spans over the end of the day
  rollover_midpoint <- (change_points[1]+24 + change_points[length(change_points)])/2 -24
  
  #adds rollover_midpoint but only if there is actually a rate period "chunk" that rolls over the day
  if(price_schedule$Period[1] == price_schedule$Period[length(price_schedule$Period)]) {
    mid_points <- append(mid_points, rollover_midpoint)
  }
  
  #create a dataframe of the own and cross elasticities of the midpoints and self point (i.e., put the stepwise elasticities into one)
  for(i in x) {
    nam <- paste("Midpoints", i, sep = ".")
    Hrs <- append(mid_points, i)
    Hrs <- Hrs[-match(price_schedule$Period[i],price_schedule$Period[mid_points])]
    #The loop above selects a set of midpoints that leaves out one midpoint based on the hour that a table is being made for (it excludes the midpoint that is in the same period as the hour of the table)
    
    Hrs24 <- append(Hrs,i) #adds the end point (the starting hour 24 hours later)
    Hrs <- if_else(Hrs<i,Hrs+24,Hrs) %>% 
      append(i+24)
    #lists "real hours" from the starting point, adding 24 to any hours before the start point
    
    periods <- price_schedule$Period[c(Hrs24)] 
    #retrieves the rate periods of each hour listed
    
    own_period <- price_schedule$Period[i]
    #retrieves rate period of the current hour
    own_period_elasticities <- filter(chosen_elasticities, Base_Hr == own_period)
    midpoint_elasticities <- own_period_elasticities$Elasticity[match(periods, Elasticities$Changed_Hr)]
    
    
    assign(nam,data.frame(Hour=Hrs,Hrs24=Hrs24, Period=periods,Elasticity = midpoint_elasticities))
    #makes a data frame named after the current hour with each of the above variables
    
  }
  
  #spline the midpoint table
  for (i in x) {
    current_hr <- eval(parse(text = sub("XX", i, "Midpoints.XX")))
    #calls current hours midpoint table
    
    Y = spline(x=current_hr$Hour,y=current_hr$Elasticity,xout=seq(min(current_hr$Hour),max(current_hr$Hour)))
    #splines elasticities to smoooth
    
    HR = Y$x
    
    ELAST = Y$y
    
    nam <- paste("Elasticities", i, sep = ".")
    
    assign(nam,data.frame(HR=HR,ELAST=ELAST,HR24 = if_else(HR<=24,HR,HR-24)))
    #makes a data frame with above variables: Hours, smoothed elasticities
  }
  ####
  
  #MATRIX####
  
  #creates our matrix based on the 24 smoothed elasticities for each hour.
  #uses a for loop to call files rather than individually
  #NOTE this matrix has each COLUMN to be used for each hour. Our excel used each ROW if trying to compare.
  
  matrix <- data.frame(Hr = c(1:24))
  for (i in x) {
    El <- eval(parse(text = sub("YY", i, "Elasticities.YY")))
    El <- El[-1,]
    El <- El[order(El$HR24),]
    matrix <- cbind(matrix, El$ELAST)
  }
  matrix<-matrix[,-1]
  colnames(matrix) <- c(1:24)
  ####
  
  ###set matrix to no cross_elasticitities
  #matrix <- read_csv("No_Cross_Matrix.csv")
  
  
  #INTERVENTION & COMMUNICATION####
  
  
  #price_change <- -0.05
  #intervention_hours <- c(12:15)
  EV_Demand <- EV_Demand %>% 
    mutate(P1 = price_schedule$P0) #Copies the initial price schedule into a new column (P1) that can then be modified to reflect the intervention
  
  EV_Demand$P1[intervention_hours] <-EV_Demand$P1[intervention_hours] + price_change #updates intervention column to implement intervention
  
  
  #Adds percentage change in price (P1p)
  EV_Demand <- EV_Demand %>% 
    mutate(P1p = (P1-P0)/P0) %>% 
    mutate(P1pC = P1p*intervention_comm_effect)
  
  
  X1p <- as.vector(0)
  for (val in x) {
    mat <- sub("XX",val, "matrix$`XX`")
    sum_prod <- crossprod(EV_Demand$P1pC,eval(parse(text = mat)))
    X1p<- append(X1p,sum_prod)
    
  } #crossprod() multiplies sumproduct of the percent change in price with each column in the matrix. This is done 24 times by the for loop rather than 24 individual times
  
  X1p <- X1p[-1] # gets rid of the first dummy entry to the variable
  EV_Demand <- mutate(EV_Demand, X1p = X1p) #add percent change in demand due to price onto EV_Demand (X1p)
  
  EV_Demand <- mutate(EV_Demand, X1 = (1+X1p)*X0) #adds new demand in kW variable (X1)
  
  ####
  
  
  #THROTTLING####
  
  #throttle_amount <- 0 #throttling amount -0.5 - 50%
  Tp <- rep(0,24)
  #throttle_hours <- c(7:11) #hours that throttling occurs
  Tp[throttle_hours] <- throttle_amount #Assigns the throttling intervention percentage chosen at the inputs at the beginning to the hours chosen then
  
  #Adds throttling percentage to each hour (Tp)
  
  EV_Demand <- EV_Demand %>% 
    mutate(Tp=Tp) %>% 
    mutate(Xt = (1+Tp)*X1)
  
  
  ####
  
  
  #SHIFTING/FINAL####
  
  #The variables below quantify the shift and net change in demand as a result of interventions, and need to be adjusted based on intervention (does not count throttling)
  
  Total_x0 <- sum(EV_Demand$X0)
  Total_xt <-sum(EV_Demand$Xt)
  
  Net_Change <- Total_xt-Total_x0
  Change_intervention <- sum(EV_Demand$Xt[intervention_hours]) - sum(EV_Demand$X0[intervention_hours])
  Change_outside_intervention <- sum(EV_Demand$Xt[-intervention_hours])- sum(EV_Demand$X0[-intervention_hours])
  
  
  
  
  EV_Demand <- mutate(EV_Demand, Xint_effect = Xt - X0)
  
  EV_Demand <- mutate(EV_Demand, MT = Max_Theory ,Xf = Xt)
  
  
  
  
  ####
  
  
  return(list(EV_Demand=EV_Demand,matrix=matrix)) #This is how to output multiple data frames from the fcn. 
  
}