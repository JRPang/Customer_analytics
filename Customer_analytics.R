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
                   "ggplot2", "reshape", "reshape2", "ggpubr","arules","arulesViz","NMF")
lapply(packages_used, library, character.only = TRUE)

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
              ungroup() %>%
              dplyr::select(Varietal, Origin, total.subscription) %>%
              arrange(desc(total.subscription))
              

product <- unique(product) %>% arrange(Varietal, desc(total.subscription), Origin)
product$varietal.code <- row.names(product)

ordered_name <- product %>%
                  group_by(Varietal) %>% 
                  summarise(total = sum(total.subscription)) %>% 
                  arrange(desc(total)) %>% 
                  dplyr::select(Varietal)
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
                  dplyr::select(name, Offer, varietal.code)
product_buyers <- transaction %>% 
                    dplyr::select(name, varietal.code) %>% unique() %>%
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


basket_set <- product_buyers_list %>% dplyr::select(cols_basket)
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
#transaction_data <- as.data.table(cast(transaction, name~Offer, fun.aggregate = sum)[,2:33]) 
transaction_data <- as.data.frame(cast(transaction, name~Offer, fun.aggregate = sum)[,2:33]) 
rownames(transaction_data) <- cast(transaction, name~Offer, sum)[,1]
colnames(transaction_data) <- c(paste0("offer.", c(1:nrow(offers))))

rows <- apply(transaction_data,1,sum)
table(rows)
cols <- apply(transaction_data,2,sum)
cols

table(unlist(transaction_data))
sparsity <- sum(unlist(transaction_data) == 0)/ (nrow(transaction_data) * ncol(transaction_data))

# Non-negative matrix factorization
set.seed(1234)
nmf_method <- "lee"
cluster_set <- c(2:5)
n_initial <- 25
sil_values <- data.frame(cluster.number = cluster_set, 
                         silhouette.consensus = rep(NA, length(cluster_set)),
                         silhouette.coef = rep(NA, length(cluster_set)),
                         silhouette.basis = rep(NA, length(cluster_set)),
                         residuals = rep(NA, length(cluster_set)))

for(i in cluster_set){
  model_search <- nmf(transaction_data, i, nmf_method, nrun = n_initial)
  metrics <- summary(model_search)
  sil_values[i-1, "silhouette.consensus"] <- as.vector(metrics["silhouette.consensus"])
  sil_values[i-1, "silhouette.coef"] <- as.vector(metrics["silhouette.coef"])
  sil_values[i-1, "silhouette.basis"] <- as.vector(metrics["silhouette.basis"])
  sil_values[i-1, "residuals"] <- as.vector(metrics["residuals"])
}

sil_values <- sil_values %>% 
                  arrange(desc(silhouette.consensus), residuals) %>% 
                  mutate(rank = row_number())

# Build NMF model with optimal cluster number determined by comparing the silhouette distance and residuals
optimal_cluster <- sil_values[sil_values["rank"] ==1, "cluster.number"]
fit <- nmf(transaction_data, optimal_cluster, nmf_method, nrun = n_initial)
summary(fit)

# customer segmentation by purchasing behaviour on promotion marketing campaigns
weight <- basis(fit)
wp <- weight / apply(weight,1,sum)

# Hard clustering 
cluster_assigned <- max.col(weight)
table(cluster_assigned)
t(aggregate(transaction_data, by=list(cluster_assigned), FUN=mean))

transaction_data <- cbind.data.frame(wp, cluster_assigned, transaction_data)
no_each_cluster <- table(transaction_data$cluster_assigned)

# customer profiling according to segmentation
coef <- as.data.frame(coef(fit)) %>% dplyr:: select(starts_with("offer"))
profile_coef <- round(t(coef), 2)
profile_group <- max.col(profile_coef)
offers <- cbind.data.frame(offers, profile_group, profile_coef)

# offers[order(offers$"1",decreasing = TRUE),1:10][1:10,]
# offers[order(offers$"2",decreasing = TRUE),1:10][1:10,]
# offers[order(offers$"3",decreasing = TRUE),1:10][1:10,]

# transaction_data[transaction_data$cluster_assigned == "1", c(5:ncol(transaction_data))]
# transaction_data[transaction_data$cluster_assigned == "2", c(5:ncol(transaction_data))]
# transaction_data[transaction_data$cluster_assigned == "3", c(5:ncol(transaction_data))]

by(transaction_data[,c(5:ncol(transaction_data))], transaction_data$cluster_assigned, FUN=colSums)

basismap(fit)
#plot.new()
frame()
coefmap(fit)

# from consensus
plot(silhouette(fit, what = 'consensus'))
# feature clustering(row)
plot(silhouette(fit, what = 'features'))
# samples clustering(column)
plot(silhouette(fit, what = 'samples'))

# PCA, SVD
