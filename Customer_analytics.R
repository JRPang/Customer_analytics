#------------------------- Description -------------------------
# Customer Analytics
# Methods: K-Mean Clustering, Market basket analysis
#
#Reference: 
# https://www.r-bloggers.com/customer-segmentation-part-1-k-means-clustering/
# http://as.wiley.com/WileyCDA/WileyTitle/productCd-111866146X.html
# http://www.salemmarafi.com/code/customer-segmentation-excel-and-r/#excel-step1
#---------------------------------------------------------------------#

#------------------------- General Settings -------------------------
rm(list=ls(all=TRUE))  # Clear environment

#add and load packages at once
packages_used <- c("xlsx","plyr","tidyverse","tidyr","data.table","Hmisc","cluster",
                   "ggplot2", "reshape", "reshape2", "ggpubr","arules","arulesViz")
lapply(packages_used, library, character.only = TRUE)

setwd("C:/Users/Jia Rong/Desktop/Project/Customer_analytics/")
data_file <- "clustering-vanilla.xlsx"

#------------------------- File Processing -------------------------
# Read offers and transaction data
offers <- read.xlsx(file=data_file,"OfferInformation")
transaction <-read.xlsx(file=data_file,"Transactions")

colnames(transaction) <- c("name","Offer")
colnames(offers) <- c("Offer", "Campaign.month", "Varietal", "Minimum.Qty.kg.", "Discount", "Origin", "Past.Peak" )
offers$Campaign.month <- factor(offers$Campaign.month, 
                                levels = c("January","February","March","April","May","June",
                                           "July","August","September","October","November","December"))
transaction$Offer <- factor(transaction$Offer)

# Descriptive statistics
# Organize the transactions and perform descriptive analysis
length(unique(transaction$name)) # number of buyers

offer_stats <- transaction %>% group_by(Offer) %>% count()
colnames(offer_stats) <- c("Offer", "number.subscription")
offers <- join(offers, offer_stats, by="Offer", type = "inner")

product <- offers %>% 
              group_by(Varietal, Origin) %>% 
              mutate(total.subscription = sum(number.subscription)) %>%
              arrange(desc(total.subscription)) %>%
              select(Varietal, Origin, total.subscription)

product <- unique(product) %>% arrange(Varietal, desc(total.subscription), Origin)
product$varietal.code <- row.names(product)

ordered_name <- product %>%
                  group_by(Varietal) %>% 
                  summarise(total = sum(total.subscription)) %>% 
                  arrange(desc(total)) %>% 
                  select(Varietal)
product$Varietal <- factor(product$Varietal, levels = ordered_name$Varietal)

ggplot(data = product, aes(x = Varietal, color = Origin, fill = Origin)) +
  geom_bar(aes(y = (total.subscription)/sum(total.subscription)), stat="identity", position = "stack") +
  labs(title = "Sales of varietal", x = "Varietal", y = "Percentage of sales") +
  scale_y_continuous(labels=scales::percent) +
  coord_flip()

#
offers %>% 
  group_by(Campaign.month) %>% 
  summarise(total = sum(number.subscription)) %>%
  ggplot(aes(x = Campaign.month, y = total, group = 1)) +
  geom_point(color = "red", size = 4) +
  geom_line() + 
  labs(title = "Total sales of campaigns over months", x = "Month of Campaign", y = "Sales")
  
# Check the correlation of discount and sales
ggscatter(offers, x = "number.subscription", y = "Discount", 
          add = "reg.line", conf.int = TRUE, 
          cor.coef = TRUE, cor.method = "pearson",
          title = "Correlation test",
          xlab = "number.subscription", ylab = "Discount")



# ---- Association rules - Market Basket Analysis ---- 

offers <- join(offers, product, by=c("Varietal","Origin"), type = "inner")

transaction <- join(transaction, offers, by=c("Offer"), type = "inner") %>%
                  select(name, Offer, varietal.code)
product_buyers <- transaction %>% 
                    select(name, varietal.code) %>% unique() %>%
                    group_by(name) %>% 
                    mutate(order = row_number())
product_buyers_list <- dcast(product_buyers, formula = name~order, value.var = c("varietal.code"))
max_product <- ncol(product_buyers_list)-1
product_buyers_list$product.subscribe <- sapply(1:nrow(product_buyers_list), function(x) 
                                                (max_product - sum(is.na(product_buyers_list[x, c(2:ncol(product_buyers_list))]) == TRUE)))
colnames(product_buyers_list) <- c("name", paste0("product.", c(1:(ncol(product_buyers_list)-2))), "product.subscribe")

# 
transaction_list <- transaction %>% group_by(name) %>% mutate(order = row_number())
transaction_list <- dcast(transaction_list, formula = name~order, value.var = c("Offer"))
transaction_list$offer.subscribe <- sapply(1:nrow(transaction_list), function(x) ((ncol(transaction_list)-1) - sum(is.na(transaction_list[x, c(2:ncol(transaction_list))]) == TRUE)))
colnames(transaction_list) <- c("name", paste0("Offer.", c(1:(ncol(transaction_list)-2))), "offer.subscribe")

# 
product_buyers_list <- join(product_buyers_list, transaction_list, by=c("name"), type = "inner")
head(product_buyers_list, 5) 
summary(product_buyers_list$product.subscribe)
summary(product_buyers_list$offer.subscribe)

rm(transaction_list, product_buyers)
# data[!complete.cases(data),]
cols_basket <- paste0("product.", c(1:max_product))


basket_set <- product_buyers_list %>% select(cols_basket)
basket_set[] <- lapply(basket_set, factor)
write.table(basket_set, file="market_basket.csv", col.names=FALSE, row.names = FALSE, 
            quote = FALSE, sep = ",", na = "") 

market_basket <- read.transactions('market_basket.csv', format = 'basket', sep=',')
summary(market_basket)
itemFrequencyPlot(market_basket, topN = 10)

# Market Basket Analysis - Association Rule(apriori)

# Training Apriori on the dataset
rules <- apriori(market_basket, parameter = list(minlen=2,maxlen=5, supp=0.05, conf=0.5),
                 control = list(verbose=F))
summary(rules)

rules.sorted <- sort(rules, by="lift")
inspect(rules.sorted)

# Visualization
plot(rules.sorted, method="graph", control=list(type="items"))
plot(rules.sorted,method="graph",interactive=TRUE,shading=NA)
plot(rules.sorted, method="paracoord", control=list(reorder=TRUE))





# ---- Clustering - Customer Segmetation ---- 

# Data manipulation
transaction$value <- 1
transaction_data <- as.data.table(cast(transaction, name~Offer, fun.aggregate = sum)[,2:33]) 
rownames(transaction_data) <- cast(transaction, name~Offer, sum)[,1]
transaction_data[] <- lapply(transaction_data, factor)
colnames(transaction_data) <- c(paste0("offer.", c(1:nrow(offers))))


# K-modes clustering 
install.packages("klaR")
library(klaR)

cluster.results <-kmodes(transaction_data, modes = 4, iter.max = 10, weighted = FALSE )
cluster.results$cluster
cluster.results



# K-means clustering 
set.seed(1)
wcss = vector()
for (i in 1:10) wcss[i] = sum(kmeans(transaction_data, i)$withinss)
plot(1:10,
     wcss, type = 'b', col = "red",
     main = paste('The Elbow Method'), xlab = 'Number of clusters', ylab = 'WCSS')

# function to compute the score for clusters
silhouette.rk <- function(cluster,dist.euclidean){
  clusters <- sort(unique(cluster$cluster))
  silh <- numeric()
  for(i in cluster$id){
    temp <- subset(cluster, id!=i)
    temp.cluster <- subset(cluster, id==i)$cluster
    same.cluster <- subset(temp, cluster == temp.cluster)
    diff.cluster <- subset(temp, cluster != temp.cluster)
    i.star <- pmin(i,same.cluster$id)
    j.star <- pmax(i,same.cluster$id)
    within <- mean(dist.euclidean[ n*(i.star-1) -
                                     i.star*(i.star-1)/2 + j.star-i.star ])
    neighbor <- min( sapply( clusters[-temp.cluster],function(j)
    {
      i.star <- pmin(i,subset(diff.cluster, cluster== j)$id)
      j.star <- pmax(i,subset(diff.cluster, cluster== j)$id)
      mean(dist.euclidean[ n*(i.star-1) - i.star*(i.star-1)/2 + j.star-i.star ])
    }
    ) )
    silh <- c(silh , (neighbor-within)/max(within, neighbor))
  }
  mean(silh)
}


# Train clustering Models 
# 4 to 6 clusters
set.seed(1)
dist.euclidean <- dist(transaction_data)
n <- attr(dist.euclidean, "Size")
no_cluster <- 5

#For K = 4 clusters, one can calculate silhouette as follows:
km_model <- kmeans(transaction_data, centers =  no_cluster, nstart = 25)
cluster <- data.frame(name = (rownames(transaction_data)), cluster = km_model$cluster)
cluster$id <- c(1:nrow(cluster))                  

print(silhouette.rk(cluster,dist.euclidean))
print((summary(silhouette(km_model$cluster,dist.euclidean)))$avg.width)

silh_metrics <- silhouette(km_model$cluster,dist.euclidean)
plot(silh_metrics)




#For K = 5 clusters, one can calculate silhouette as follows:
set.seed(1)
km_model <- kmeans(transaction_data, centers =  4, nstart = 25)
cluster <- data.frame(name = (rownames(transaction_data)),
                      cluster = km_model$cluster, id = 1:nrow(cluster) )
print(silhouette.rk(cluster,dist.euclidean))
print((summary(silhouette(km_model$cluster,dist.euclidean)))$avg.width)




km_model4 <- kmeans(transaction_data, centers =  4, nstart = 25)
offers.temp <- cbind(offers, (t(km_model$centers)))

offers.temp[order(offers.temp$"1",decreasing = TRUE),1:6][1:10,]
offers.temp[order(offers.temp$"2",decreasing = TRUE),1:6][1:10,]
offers.temp[order(offers.temp$"3",decreasing = TRUE),1:6][1:10,]
offers.temp[order(offers.temp$"4",decreasing = TRUE),1:6][1:10,]

cluster <- data.frame(name = (rownames(transaction_data)),cluster = km_model$cluster)
offers_by_cluster <- merge(transaction, cluster, all.x = T)



temp <- cast(offers_by_cluster,Offer~cluster,sum) # or sum
temp <- cbind(offers,temp)
temp[order(temp$"1",decreasing = TRUE),1:6][1:10,]
temp[order(temp$"2",decreasing = TRUE),1:6][1:10,]
temp[order(temp$"3",decreasing = TRUE),1:6][1:10,]
temp[order(temp$"4",decreasing = TRUE),1:6][1:10,]



#For K = 4 clusters, one can calculate silhouette as follows:
set.seed(1)
dist.euclidean <- dist(transaction_data)
n <- attr(dist.euclidean, "Size")

km_model <- kmeans(transaction_data,4,nstart=25)
cluster <- data.frame(name = (rownames(transaction_data)),
                      cluster = km_model$cluster, id = 1:nrow(cluster) )
print(silhouette.rk(cluster,dist.euclidean))

print((summary(silhouette(km_model$cluster,dist.euclidean)))$avg.width)

#For K = 5 clusters, one can calculate silhouette as follows:
set.seed(1)
km_model <- kmeans(transaction_data,5,nstart=25)
cluster <- data.frame(name = (rownames(transaction_data)),
                      cluster = km_model$cluster, id = 1:nrow(cluster) )
print(silhouette.rk(cluster,dist.euclidean))
print((summary(silhouette(km_model$cluster,dist.euclidean)))$avg.width)

# spherical kmeans method(skmeans in r,dissimilarity measure is based on correlation-based distance)
library(skmeans)
set.seed(1)
sk.out <- skmeans(as.matrix(transaction_data),5,method="genetic")
cluster <- data.frame(name=(rownames(transaction_data)),cluster=sk.out$cluster,id=1:nrow(cluster))
offers_by_cluster <- merge(transaction,cluster,all.x=T)
temp <- cast(offers_by_cluster,offers~cluster,sum)
temp <- cbind(offers,temp)

temp[order(temp$"1",decreasing = TRUE),1:6][1:10,]
temp[order(temp$"2",decreasing = TRUE),1:6][1:10,]
temp[order(temp$"3",decreasing = TRUE),1:6][1:10,]
temp[order(temp$"4",decreasing = TRUE),1:6][1:10,]
temp[order(temp$"5",decreasing = TRUE),1:6][1:10,]

print(silhouette.rk(cluster,dist.euclidean))
print((summary(silhouette(sk.out$cluster,dist.euclidean)))$avg.width)
