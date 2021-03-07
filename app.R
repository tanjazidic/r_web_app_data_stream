library(shiny)
library(magrittr)
library(jsonlite)
library(ggplot2)
library(shinyjs)
library(shinydashboard)
library(hashmap)
library(dplyr)
library(lubridate)
library(SparkR)
library(RSQLite)
library(DBI)
library(shinyalert)
library(reticulate)
library(hashmap)
library(Metrics)
library(caret)


# Python script with code for Consumer and methods for creating, polling and checking topics
source_python('consumerScript.py')

#SparkR configuration
spark_path <- 'C:/hadoop-2.9.1/spark'
if (nchar(Sys.getenv("SPARK_HOME")) < 1) {
  Sys.setenv(SPARK_HOME = spark_path)
}
library(SparkR, lib.loc = c(file.path(Sys.getenv("SPARK_HOME"), "R", "lib")))
sparkR.session(master = "local[*]", sparkConfig = list(spark.driver.memory = "2g",
                                                       spark.driver.extraLibraryPath = "org.apache.spark:spark-sql-kafka-0-10_2.11:2.4.3" ))

# Database and user managment
mydb <- dbConnect(RSQLite::SQLite(), "users.sqlite")
user_base <- data.frame(
  user = c("user", "admin"),
  password = c(
    digest::digest("user", algo = "md5"),
    digest::digest("admin", algo = "md5")
  ),
  permissions = c("user", "admin"),
  graph1 = c(
    "Maximum-MAX_CALL_DURATION_LAST_1D",
    "Minimum-MIN_CALL_DURATION_LAST_1D"
  ),
  graph2 = c(
    "Maximum-MAX_CALL_DURATION_LAST_1D",
    "Minimum-MIN_CALL_DURATION_LAST_1D"
  ),
  graph3 = c(2, 2),
  graph4 = c(100, 100),
  stringsAsFactors = FALSE
)



if (!DBI::dbExistsTable(mydb, "users")) {
  table <- "
  CREATE TABLE users (
  user TEXT,
  password TEXT,
  permissions TEXT,
  graph1 TEXT,
  graph2 TEXT,
  graph3 INT,
  graph4 INT,
  PRIMARY KEY(user)
  )"
  
  dbExecute(mydb, table)
  DBI::dbWriteTable(mydb, "users", user_base, append = TRUE)
}




# Part of the application where the user interface is defined
# It uses shiny package shinydashboard for making a user-friendly interface
# First page is login page where user needs to enter its credentials for logging
# All other tabs are created dynamically at the server side of the application, with reference of output variable "tabs" 

ui <- 
  dashboardPage(
    dashboardHeader(title = "RKafka",
                    tags$li(class="dropdown",
                            tags$li(class="dropdown",shinyjs::hidden(
                              shiny::actionButton("logout", "Log Out", class = "btn-danger pull-right", style = "color: white;")
                            )))),
    dashboardSidebar(sidebarMenuOutput("menu")),
    dashboardBody(
      shinyjs::useShinyjs(),
      
      useShinyalert(),
      
      shiny::div(
        id = "panel",
        style = "width: 500px; max-width: 100%; margin: 0 auto; padding: 20px;",
        shiny::wellPanel(
          shiny::tags$h2("Please Log In", class = "text-center", style = "padding-top: 0;"),
          
          shiny::textInput("username" , "Username"),
          
          shiny::passwordInput("password", "Password"),
          
          shiny::div(
            style = "text-align: center;",
            shiny::actionButton("button", "Log in", class = "btn-primary", style = "color: white;")
          ),
          
          shinyjs::hidden(shiny::div(
            id = "error",
            shiny::tags$p(
              "Invalid username or password",
              style = "color: red; font-weight: bold; padding-top: 5px;",
              class = "text-center"
            )
          ))
        )
      ),
      
      
      
      
      #  tabPanel(
      uiOutput("tabs")
    )
  )
# Function that takes as an argument: an instance of Consumer c
# And uses function "get_df" of Python script to get new messages of the topic
get_new_data <- function(c) {
  data <- get_df(c)
  return(data)
}

# Function that prepares reactive variable values for new topic
values<<-NULL
prepare_values <-function(topic) {
  if(is.null(values[[topic]])){
    values[[topic]]<<-NULL
  }
}

# Function that takes an instance of Consumer and name of the topic as arguments
# And binds messages that are already saved in variable values with new data
update_data <- function(c,topic) {
  values[[topic]] <<- rbind(get_new_data(c), values[[topic]])
  values[[topic]]
}

# Server side of the application where first all reactive variables are declared
# Variable topics for each topic holds as argument consumer for that topic
# Variable valueBoxReacts holds the counter with number of messages produced for each topic
# Variable current holds name of the current topic (active, selected on the side menu)
# Variable choices holds for each topic all attributes of that topic so it can be used for drop down lists
# Variable graphs for each topic holds all graphs that the user defines for that topic
# Variable models saves predictive models that are added by the user
# Variable argumentsForModel holds all necessary stuff for building the predictive model
server <- function(input, output, session) {
  topics <- reactiveValues()
  valueBoxReacts <- reactiveValues()
  current <- reactiveValues()
  values <- reactiveValues()
  choices <- reactiveValues()
  types <- reactiveValues()
  graphs <- reactiveValues()
  models <- reactiveValues()
  argumentsForModel <- reactiveValues()
  
  
  
  credentials <-
    shiny::reactiveValues(user_auth = FALSE, info = NULL)
  shinyjs::hide(id = "add-topic")
  shinyjs::hide(id = "Sidebar")
  shinyjs::hide(id = "auth")
  shinyjs::hide(id = "auth2")
  
  
  
  
  initialized <- hashmap(c("admin", "user"), c(FALSE, FALSE))
  for (user in user_base$user) {
    initialized[[user]] <- FALSE
    
  }
  
  # Depending on what kind of user is logged in we are making visible certain elements
  observe({
    
    if (credentials$user_auth) {
      if (credentials$info$permissions == "admin") {
        shinyjs::show(id = "add-topic")
        lapply(names(reactiveValuesToList(topics)), function(t){
          shinyjs::show(id = paste0(t,"add-visualization"))
          shinyjs::show(id = paste0(t,"graphs"))
        })
        
      }
      else{
        shinyjs::hide(id="add-visualization")
        shinyjs::hide(id="graphs")
      }
      lapply(names(reactiveValuesToList(topics)), function(t){
        shinyjs::show(id = paste0(t,"box1"))
        shinyjs::show(id = paste0(t,"box2"))
        shinyjs::show(id = paste0(t,"auth"))
      })
      shinyjs::show(id = "auth2")
      shinyjs::show(id="Sidebar")
      
    } else {
      shinyjs::hide(id = "Sidebar")
      shinyjs::hide(id = "add-topic")
      shinyjs::hide(id = "box1")
      shinyjs::hide(id = "box2")
      shinyjs::hide(id = "auth")
      shinyjs::hide(id = "auth2")
      
    }
    
    
  })
  
  # Here is where output variable tabs is used to create all tabs that are used in dashboard
  # Variable items holds all tabs, including tab for creating new topic and for all the topics that have been added
  # There is a loop through variable topics and for each topic new tab is created with
  # Form for adding new predictive models, box with types of the attributes,
  # Box for visualisation of models for that topic and its metrics,
  # Form for adding new visualisation and then for each graph in variable graphs is rendered
  # Box for each of the graph
  output$tabs <- renderUI({
    items <-     c(lapply(names(reactiveValuesToList(topics)),function(t) {
      counter<<-0
      # To keep track of what tab is currently active based on what menu item is selected
      # Without this part when new visualisation is added the right topic wouldn't be chosen
      if(length(current$topic) != 0){
        if(t==current$topic){
          activeClass<-"active"
        }
        else {
          activeClass<-""
        }
      }
      else {
        activeClass<-""
      }
      
      tabItem(tabName = t,class=activeClass,
              fluidRow(
                id = paste0(t,"auth"),
                shiny::column(
                  width=6,
                  box(
                    title = "Attributes",
                    status = "danger",
                    solidHeader = TRUE,
                    collapsible = FALSE,
                    renderPrint((types[[t]]))
                  ),
                  
                  
                  box(
                    id = paste0(t,"add-model"),
                    title = "Add new predictive model",
                    solidHeader = TRUE,
                    status = "primary",
                    selectInput(paste0(t,"typeModel"),"Type of model", choices = c("Regression","Classification")),
                    selectInput(paste0(t,"algorithm"),"Algorithm",
                                choices = c("Logistic regression(classification)" = "spark.logit",
                                            "Naive Bayes(classification)" = "spark.naiveBayes",
                                            "Decision Tree(both)" = "spark.decisionTree",
                                            "Random forest(both)" = "spark.randomForest", 
                                            "LinearSVM(classification)" ="spark.svmLinear")),
                    
                    selectInput(paste0(t,"scoring"),"Scoring stream", choices = c(current$topic)),
                    checkboxInput("build_file","Use csv input file to build?"),
                    conditionalPanel(
                      condition = "input.build_file == false",
                      selectInput(paste0(t,"build"), "Build stream",choices = c(current$topic)
                      )),
                    conditionalPanel(
                      condition = "input.build_file == true",
                      fileInput(paste0(t,"bfile"), "Choose CSV File to build the model",
                                accept = c(
                                  "text/csv",
                                  "text/comma-separated-values,text/plain",
                                  ".csv")
                      )),
                    selectInput(paste0(t,"predictedVariable"), "Variable to predict:", choices = choices[[t]]),
                    numericInput(paste0(t,"ratio"), "Ratio between build/validation:", 0.5, min = 0, max = 1, step = 0.05),
                    checkboxGroupInput(paste0(t,"variables"), "Choose variables to build the model:",
                                       choiceNames = choices[[t]],
                                       choiceValues = choices[[t]],
                                       inline=TRUE
                    ),
                    conditionalPanel(
                      condition = "input.build_file == false",
                      numericInput(paste0(t,"rebuild"), "When to do rebuild(min):", 10, min = 1, max = 100),
                      radioButtons(paste0(t,"rebuildtype"), "How to rebuild:",
                                   c("All available data"="all", "Only new data"="new"))
                    ),
                    actionButton(paste0(t,"addModel"), "Add new model", class = "button-primary", status="success")
                  ),
                  lapply(models[[t]],function(m){
                    box(
                      title = paste(m$type,"model","for",m$label,"(",m$algorithm,")"),
                      
                      
                      id = paste0(t,m$type,m$algorithm,m$label)
                      ,
                      status = "danger"
                      ,
                      solidHeader = TRUE
                      ,
                      collapsible = TRUE
                      ,
                      valueBoxOutput(paste0(t,m$type,m$label,m$algorithm,"value"), width=NULL),
                      if(m$type == "Classification"){
                        verbatimTextOutput(paste0(t,m$type,m$label,m$algorithm,"table"))
                      },
                      plotOutput(paste0(t,m$type,m$label,m$algorithm), height = 320),
                      actionButton(paste0(t,"remove"),"Remove model")
                      
                    )
                  })),
                shiny::column(
                  id=paste0(t,"graphs"),
                  width=5,
                  box(
                    height = 500,
                    id = paste0(t,"add-visualization"),
                    title = "Add new visualisation:",
                    solidHeader = TRUE,
                    status = "danger",
                    
                    selectInput(paste0(t,"variableY"), "Variable Y:", choices = choices[[t]]),
                    selectInput(paste0(t,"variableX"), "Variable X:", choices = union("-",choices[[t]]),selected="-"),
                    selectInput(paste0(t,"type"), "Type of visualisation:", choices = c("Bar","Line")),
                    actionButton(paste0(t,"addVisual"), "Add", class = "button-primary")
                    
                    
                  ),
                  box(valueBoxOutput(paste0(t,"value1"), width = NULL)),
                  lapply(graphs[[t]],function(g){
                    counter<<-counter+1
                    box(
                      title = paste("Graph",counter),
                      id = paste0(t,counter)
                      ,
                      status = "danger"
                      ,
                      solidHeader = FALSE
                      ,
                      collapsible = TRUE
                      ,
           
                      plotOutput(paste0(t,"grid",counter), height = 320) 
                    )
                  }
                  )
                )
                
              ))}
      
      
    ),
    list(tabItem(tabName = "createTopic",
                 div(
                   id = "add-topic", box(
                     title = "Subscribe to new topic",
                     status = "warning",
                     solidHeader = TRUE,
                     textInput("server", "Bootstrap servers", ""),
                     textInput("name", "Topic name", ""),
                     actionButton("addTopic", "Subscribe", class = "button-primary")
                   )))
        
         
    )
    )
    do.call(tabItems,items)
    
  })
  
  # Part of the code where it is observed when the button for adding visualisation is clicked for the current topic
  # First it is prepared the name of the input variable and then we can make a function for observing the event
  # Input variables are removed from their reactive nature with command isolate so that by adding new
  # Graph it don't change graphs that are already added
  # Based on whether X value is left empty, it is substituted by number of data in the stream
  # And now it is time to add new graph (line or bar) to the collection of all graph of that topic
  # 
  observe({
    inputName<-paste0(current$topic,"addVisual")
    observeEvent(input[[inputName]], {
      t=current$topic
      isolate(y_value <- input[[paste0(t,"variableY")]])
      isolate(x_value <- input[[paste0(t,"variableX")]])
      isolate(type <- input[[paste0(t,"type")]])
      
      
      if(type == 'Bar'){
        if(x_value=="-"){
          graph<-
            renderPlot({
              g<-ggplot(data=values[[t]], aes_string(x=as.numeric(row.names(values[[t]])), y=y_value)) +xlab("Time")+ geom_bar(stat="identity") + ggtitle(paste("Topic",t,"\nPlot of\n",y_value,"by time"))
              g
            })
        }
        else {
          graph<-
            renderPlot({
              g<-ggplot(data=values[[t]], aes_string(x=x_value, y=y_value)) + geom_bar(stat="identity") + ggtitle(paste("Topic",t,"\nPlot of\n",y_value,"by",x_value))
              g
            })
        }
      }
      else {
        if(x_value=="-"){
          graph<-
            renderPlot({
              g<-ggplot(data=values[[t]], aes_string(x=as.numeric(row.names(values[[t]])), y=y_value)) +xlab("Time")+ geom_point() + geom_line() + ggtitle(paste("Topic",t,"\nPlot of\n",y_value,"by time"))
              g
            })
        }
        else {
          graph<-
            renderPlot({
              g<-ggplot(data=values[[t]], aes_string(x=x_value, y=y_value)) + geom_point() + geom_line() + ggtitle(paste("Topic",t,"\nPlot of\n",y_value,"by",x_value))
              g
            })
        }
      }
      graphs[[t]]<-append(graphs[[t]],graph)
      
    })
    
    
  })
  # Function that responds to subscribing to a new topic
  # Input variables are the name of the topic and bootstrap servers
  # First we check if all the parameters are entered
  # Then there is a check whether the topic exists on that bootstrap server
  # If all is good, we proceed to make a new consumer to that topic and save it to reactive values "topics"
  # Save first message from received from topic to variable, and prepare choices for drop-down list
  # If there is any problems, error message is generated
  observeEvent(input$addTopic, {
    if (input$name != '' && input$server != '') {
      if(input$name %in% names(reactiveValuesToList(topics))){
        shinyalert("Error", "That topic is already attached", type = "error")
      }
      
      if(!check_topic(input$server,input$name)){
        shinyalert("Error", "Topic doesn't exist", type = "error")
      }
      
      else {
        
        c=create_consumer(input$name,input$server)
        
        shinyalert("Success", "New Topic Added", type = "success")
        topics[[input$name]]=c
        
        t=input$name
        prepare_values(t)
        
        
        values[[t]] <- get_new_data(topics[[t]])
        types_of_attr <- sapply(values[[t]],class)
        types[[t]] <- as.data.frame(types_of_attr)
        
        
        choices[[t]] <- colnames(values[[t]])
        updateTextInput(session, "name", value = "")     
        updateTextInput(session, "server", value = "")   
        
        
      }
    } else {
      shinyalert("Error", "Server name or topic is empty", type = "error")
    }
    
  })
  
  # Part of the code that deals with adding arguments received from the user form for new predictive model
  # It basically just saves all the arguments in the object m, and then saves object m to the reactive value argumentsForModel
  # The only thing that we do here is to read the csv file into the R dataframe, if the build data is csv file
  # And also set rebuild time to 0 since it is a csv file
  # If build file is not csv file then we take build as the reactive variable "values", which hold all the messages
  # Received from the Consumer of the topic
  observe({
    inputName<-paste0(current$topic,"addModel")
    
    observeEvent(input[[inputName]], {
      t = current$topic
      print(t)
      m<<-NULL
      m$type <- input[[paste0(t,"typeModel")]]
      m$algorithm <- input[[paste0(t,"algorithm")]]
      m$scoringStream <- input[[paste0(t,"scoring")]]
      m$ratio <- input[[paste0(t,"ratio")]]
      m$label <- input[[paste0(t,"predictedVariable")]]
      m$sysdate <- input[[paste0(t,"sysdate")]]
      m$variables <- input[[paste0(t,"variables")]]

      if(input$build_file == TRUE) {
        
        buildFile <- input[[paste0(t,"bfile")]]
        m$build <- read.csv(buildFile$datapath) #pretvorimo csv u data frame
        m$rebuildTime <- 0
      }
      else { #inace je build file stream
        m$rebuildTime <- input[[paste0(t,"rebuild")]]
        buildStream <- input[[paste0(t,"build")]]
        m$build <- values[[buildStream]] #u varijablu build stavljamo dataframe od tog topica
        m$rebuildtype <- input[[paste0(t,"rebuildtype")]]
        
      }
      
      name <- paste0(t,m$type,m$label,m$algorithm)
      m$name = name
      
      argumentsForModel[[t]][[name]] <- m
    })
  })

  
  
  # Part of the code that deals with model building
  # We iterate over the arguments for the model and for each of them we are building new predictive model
  # First we check whether the rebuild time is set to number different from zero (meaning build is a stream of data)
  # if it is we add invalidateLater function with argument to when to do the rebuild
  # If we are in the rebuild phase for some model, we check whether user choose to do it with all data or just new
  # After all this we create new Spark Dataframe and divide it into two dataframes (build and validation)
  # Then we use fit function on the build set to make a new predictive model
  # After that we save the model on the file system and validate on the validation data
  # After that we load the model for the predictions
  # We make predictions on the incoming data (topic stream), and plot different metrics based on the type of models
  observe({
    lapply(names(reactiveValuesToList(topics)), function(t){
      lapply(argumentsForModel[[t]],function(m){
        print(m$name)
        if(m$rebuildTime != 0){
           invalidateLater(m$rebuildTime*60000,session)
           m$build <- isolate(values[[t]])
          
        }
        
        if(!is.null(m$metrics)){ #metrika nije nula znaci model je vec izgraden znaci ovo je rebuild
          if(m$rebuildtype == "new"){
            invalidateLater(m$rebuildTime*60000,session)
           # print(values[[t]])
           # print(m$build)
            m$build <- setdiff(isolate(values[[t]]),m$build)
          }
          else {
            invalidateLater(m$rebuildTime*60000,session)
            m$build <- isolate(values[[t]])
          }
        }
          df <- as.DataFrame(m$build)
          df <- withColumnRenamed(df,m$label,"label")
          #print(head(df))
          # splitting build data into build and validation
          df_list <- randomSplit(df,c(m$ratio,(1-m$ratio)))
          buildDF <- select(df_list[[1]],c(m$variables,"label"))
          validationDF <- df_list[[2]]
          # Fit a model to the build set
          # if the algorithm is DT or RF we need to specify for what model are we building (cuz they work on both)
          if(m$algorithm == "spark.decisionTree" | m$algorithm == "spark.randomForest") {
            model <- do.call(m$algorithm, list(buildDF, label ~ .,type=tolower(m$type)))
          }
          else {
            model <- do.call(m$algorithm, list(buildDF, label ~ .))
          }
          print(summary(model))
          
          saveRDS(model,paste0("./",m$name))
          
          
          predictions <- predict(model,validationDF)
          #print(head(predictions))
          new_df <- as.data.frame(predictions)
          actual <- new_df$label
          predict <- new_df$prediction
        
          
          if(m$type == "Regression"){ #print RMSE
            rmse <- rmse(actual,predict)
            m$metrics <- rmse
            
          }
          else { #print classsification matrix
            matrix <- confusionMatrix(table(actual,predict))
            m$metrics <- matrix
          }
          
          
          m$model <- model
          #Save build model in the variable models
          isolate(models[[t]][[m$name]] <- m)
          
          shinyalert("Success", "New Model Added", type = "success")
          
          #Load model and make predictions
          scoring_model <- readRDS(paste0("./",m$name))
          kafkaDF<<-data.frame()
          metrika <<- data.frame(matrix(ncol = 1, nrow = 0))
          base::colnames(metrika) <- c("metric")
          name <- m$name
        
          
          if(m$type == "Classification") {
            output[[paste0(name,"value")]] <-
              renderValueBox({
                confMatrix <- m$metrics
                valueBox(
                  formatC(
                    confMatrix$overall['Accuracy']
                  )                 ,
                  "Performance Metrics - Accuracy"
                   ,
                  icon = icon("chart-line")
                  ,
                  color = "red"
                )
              })
            
            output[[paste0(name,"table")]] <-
              renderPrint({
                confMatrix <- m$metrics
                confMatrix$table
              })
            
            output[[name]] <-
              renderPlot({
                kafkaDF <<- rbind(kafkaDF,head(values[[t]],n=1))
                sparkDF <- as.DataFrame(kafkaDF)
                predictions <- predict(scoring_model,sparkDF)
               
                visual <- collect(predictions)
                g<-ggplot(data=visual, aes_string(x=as.numeric(row.names(visual)), y="prediction", col = "prediction")) + geom_line() + geom_point() + xlab("stream") + ylab("prediction")
                g
              })
            
          }
          
          
          else {
            
            output[[paste0(name,"value")]] <-
              renderValueBox({
                valueBox(
                  formatC(
                    m$metrics,
                    format = "d",
                    big.mark = ','
                  )
                  ,
                  
                  "Performance Metrics - RMSE"
                  ,
                  icon = icon("chart-line")
                  ,
                  color = "red"
                )
              })
            output[[name]] <-
              renderPlot({
                kafkaDF <<- rbind(kafkaDF,head(values[[t]],n=1))
                sparkDF <- as.DataFrame(kafkaDF)
                pred <- predict(scoring_model,sparkDF)
                pred <- withColumnRenamed(pred,m$label,"label")
                visual <- collect(pred)
                metrika<<-rbind(metrika,data.frame(metric=rmse(visual$label,visual$prediction)))
                g<-ggplot(data=metrika, aes_string(x=as.numeric(row.names(metrika)), y = "metric")) + geom_line() + geom_point() + xlab("stream") + ylab("RMSE")
                g
              })
          
          }
          
         
        })
      })
  })
  
  
  
  
  # Observe event  of menu selecting
  # And save current selected topic in reactive value
  observeEvent(input$menu, {
    lapply(names(reactiveValuesToList(topics)),function(t) {
      if(input$menu == t){
        current$topic=t
      }
    })
  })
  
  # Function that for each topic generate output for value box
  # And prints out the number of messages that have been consumed
  observe({
    lapply(names(reactiveValuesToList(topics)),function(t){
      plotname <- paste0(t,"value1")
      output[[plotname]]<-
        renderValueBox({
          req(credentials$user_auth)
          values[[t]]<-update_data(topics[[t]],t)
          valueBoxReacts[[t]] <- nrow(values[[t]])
          #using this every 1 sec we are polling new msg from the topic and it is saved into variable values
          invalidateLater(1000, session)
          valueBox(
            formatC(
              valueBoxReacts[[t]],
              format = "d",
              big.mark = ','
            )
            ,
            "Total number of messages"
            ,
            icon = icon("stats", lib = 'glyphicon')
            ,
            color = "green"
          )
        })
    })
  })
  
  # Function that for each topic and for each graph creates output variable
  # That plots out the graph on the dashboard
  observe({
    lapply(names(reactiveValuesToList(topics)), function(t){
      counter<<-0
      lapply(graphs[[t]],function(g){
        counter<<- counter+1
        plotname <- paste0(t,"grid",counter)
        output[[plotname]] <- g
      })
    })
  })
  
  observe({
    inputName <- paste0(current$topic,"remove")
      observeEvent(input[[inputName]], {
        t<-current$topic
        argumentsForModel[[t]] <- NULL
        models[[t]] <- NULL
        
      })
    })

  
  
  # Part of the code where menu is generated as output variable
  # Main part of the menu is item Topics with subitems containing all topics that are added dynamically
  # If user is an admin then menu item for adding new topic is created
  output$menu <- renderMenu({
    req(credentials$user_auth)
    menu <-
      sidebarMenu(
        id="menu",
        menuItem(
          "Topics",
          icon = icon("bar-chart-o"),
          startExpanded = TRUE,
          lapply(names(reactiveValuesToList(topics)),function(t) {
            menuSubItem(t, tabName = t)
          })
        ),
        
        if (credentials$info$permissions == "admin") {
          menuItem("Create Topic",
                   tabName = "createTopic",
                   icon = icon("cloud"))
        }
      )
    menu
  }) 
  
  ###BAZA I LOGIN LOGOUT
  
  observeEvent(input$button, {
    username <- input$username
    
    password <- digest::digest(input$password, algo = "md5")
    user <- data.frame(username, password)
    #print(user)
    res <- dbSendQuery(mydb, "SELECT * FROM users")
    users <- data.frame(dbFetch(res))
    if (nrow(merge(user, users)) > 0) {
      shinyjs::hide(id = "panel")
      shinyjs::show(id = "logout")
      shinyjs::hide(id = "error")
      
      credentials$info <- subset(users, user == username)
      credentials$user_auth <- TRUE
      
      print(credentials$info)
      
    }
    else {
      shinyjs::show(id = "error")
      
    }
  }) 
  observeEvent(input$logout, {
    initialized[[credentials$info$user]] <<- FALSE
    res <- dbSendQuery(mydb, "SELECT * FROM users")
    users <- data.frame(dbFetch(res))
    users2 <- users
    users2[users2$user == credentials$info$user,]$graph2 <-
      input$graph2
    
    users2[users2$user == credentials$info$user,]$graph1 <-
      input$graph1
    
    users2[users2$user == credentials$info$user,]$graph3 <-
      input$graph3
    
    users2[users2$user == credentials$info$user,]$graph4 <-
      input$graph4
    DBI::dbWriteTable(mydb, "users", users2, overwrite = TRUE)
    
    
    dbClearResult(res)
    credentials$user_auth <- FALSE
    credentials$info <- NULL
    
    shinyjs::show(id = "panel")
    shinyjs::hide(id = "logout")
    shinyjs::hide(id = "error")
    shinyjs::hide(id = "Sidebar")
    shinyjs::hide(id = "add-topic")
    
    
    shinyjs::hide(id = "auth2")
    lapply(names(reactiveValuesToList(topics)), function(t){
      shinyjs::hide(id = paste0(t,"box1"))
      shinyjs::hide(id = paste0(t,"add-visualization"))
      shinyjs::hide(id = paste0(t,"box2"))
      shinyjs::hide(id = paste0(t,"auth"))
      shinyjs::hide(id = paste0(t,"graphs"))
    })
    
  })
  
  session$onSessionEnded(function() {
    # DBI::dbDisconnect(mydb)
    sparkR.session.stop()
    #  print("disconnected")
  })
  
  
}



shinyApp(ui = ui, server = server)
