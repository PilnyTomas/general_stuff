#pragma once
#include <Arduino.h>

#define PRINT_DEBUG_LEVEL 1

/*
static inline void DEBUGLN(const char* x){
  if(PRINT_DEBUG){
   Serial.println(x);
   Serial.flush();
  }
} // debug

#define DEBUGF(format,args...) \
  if(PRINT_DEBUG) {      \
    Serial.printf(format, ## args); Serial.flush(); \
  }
*/

static inline void DEBUGLN(int level, int spaces, const char* x){
  if(PRINT_DEBUG_LEVEL >= level){
   for(int i=0;i<spaces;++i){Serial.print(" ");}
   Serial.println(x);
   Serial.flush();
  }
} // debug

#define DEBUGF(level, spaces, format, args...) \
  if(PRINT_DEBUG_LEVEL >= level){      \
    for(int i=0;i<spaces;++i){Serial.print(" ");}\
    Serial.printf(format, ## args); Serial.flush(); \
  }

/*
static inline void FORCE_DEBUGLN(const char* x){
   Serial.println(x);
   Serial.flush();
} // debug

#define FORCE_DEBUGF(format,args...) Serial.printf(format, ## args); Serial.flush();
*/
