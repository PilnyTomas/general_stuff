#pragma once

#define PRINT_DEBUG 1 // 1=print debug outputs; 0=ignore the function
static inline void DEBUGLN(const char* x){
  if(PRINT_DEBUG){
   Serial.println(x);
  }
} // debug

#define DEBUGF(format,args...) \
  if (PRINT_DEBUG) {      \
    Serial.printf(format, ## args);    \
  }

