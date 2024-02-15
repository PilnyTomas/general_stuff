#!/bin/bash
# Check if the correct number of arguments is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <chip> [elf_file]"
    exit 1
fi

chip="$(echo "${1}" | tr '[:upper:]' '[:lower:]')"

#OPENOCD_BIN="/home/pilnyt/nuttx-all/openocd-esp32/src/openocd"
OPENOCD_BIN="/home/pilnyt/.espressif/tools/openocd-esp32/v0.12.0-esp32-20230419/openocd-esp32/bin/openocd"
#OPENOCD_BIN="openocd"
openocd_cfg=""

#thbreak="ws2812esp32_main" # Temporary Hardware Breakpoint
#thbreak="rmt_open"
#thbreak="rmt_write"
#thbreak="esp32s3_periph_module_enable"
#thbreak="board_rmt_initialize"
#thbreak="esp32_rmtinitialize"
#thbreak="esp32s3_rmtinitialize"
#thbreak="esp32s3_perip_clk_init"
#thbreak="esp32s3_bringup"
#thbreak="rmt_open"
thbreak="rmt_load_tx_buffer"


#extrabreak=""
#extrabreak="esp32s2_bringup.c:220"
#extrabreak="rmt_load_tx_buffer"
#extrabreak="\"break rmt_setup\""
#extrabreak="rmt_open"
extrabreak="rmt_interrupt"
#extrabreak="rmt_write"

elf_file="nuttx"
#elf_file="${2}"

# ll ~/.espressif/tools/openocd-esp32/v0.12.0-esp32-20230419/openocd-esp32/share/openocd/scripts/board/ | grep esp32
# ll ~/nuttx-all/openocd-esp32/tcl/board/ | grep esp32

case "${chip}" in
  "esp32")
    GDB_BIN="xtensa-esp32-elf-gdb"
    MCU="esp32"
    #openocd_cfg="board/esp32-devkitc.cfg"
    #openocd_cfg="board/esp32-bridge.cfg"
    #openocd_cfg="board/esp32-ethernet-kit-3.3v.cfg"
    #openocd_cfg="board/esp32-solo-1.cfg"
    #openocd_cfg="board/esp32-wrover.cfg"
    #openocd_cfg="board/esp32-wrover-kit-1.8v.cfg"
    openocd_cfg="board/esp32-wrover-kit-3.3v.cfg"
    ;;
  "esp32s2")
    GDB_BIN="xtensa-esp32s2-elf-gdb"
    MCU="esp32s2"
    openocd_cfg="board/esp32s2-kaluga-1.cfg"
    #openocd_cfg="board/esp32s2-brigde.cfg"
    ;;
  "esp32s3")
    GDB_BIN="xtensa-esp32s3-elf-gdb"
    MCU="esp32s3"
    openocd_cfg="board/esp32s3-builtin.cfg"
    # openocd_cfg="board/esp32s3-bridge.cfg"
    # openocd_cfg="board/esp32s3-builtin.cfg"
    # openocd_cfg="board/esp32s3-ftdi.cfg"
    ;;
  "esp32c2")
    GDB_BIN="xtensa-esp32c2-elf-gdb"
    MCU="esp32c2"
    openocd_cfg="board/esp32c2-bridge.cfg"
    # openocd_cfg="board/esp32c2-ftdi.cfg"
    ;;
  "esp32c3")
    GDB_BIN="xtensa-esp32c3-elf-gdb"
    MCU="esp32c3"
    openocd_cfg="board/esp32c3-devkit.cfg"
    # openocd_cfg="board/esp32c3-bridge.cfg"
    # openocd_cfg="board/esp32c3-builtin.cfg"
    # openocd_cfg="board/esp32c3-ftdi.cfg"
    ;;
  "esp32c6")
    GDB_BIN="xtensa-esp32c6-elf-gdb"
    MCU="esp32c6"
    openocd_cfg="board/esp32c6-devkit.cfg"
    # openocd_cfg="board/esp32c6-bridge.cfg"
    # openocd_cfg="board/esp32c6-builtin.cfg"
    # openocd_cfg="board/esp32c6-ftdi.cfg"
    ;;
  "esp32h2")
    GDB_BIN="xtensa-esp32h2-elf-gdb"
    MCU="esp32h2"
    openocd_cfg="board/esp32h2-generic.cfg"
    # openocd_cfg="board/esp32h2-bridge.cfg"
    # openocd_cfg="board/esp32h2-builtin.cfg"
    # openocd_cfg="board/esp32h2-ftdi.cfg"
    ;;
  # Add more chips as needed
  *)
    echo "Unsupported chip: ${chip}"
    exit 1
    ;;
esac

function flash {
  esptool.py -c "${chip}" write_flash "${elf_file}"
}

function attach {
  pkill -f openocd
  $OPENOCD_BIN --version
  #OPENOCD_COMMAND="$OPENOCD_BIN -s tcl -c \"set ESP_RTOS none\" -c \"set ESP32_ONLYCPU 1\" -c \"set ESP_FLASH_SIZE 0\" -f \"${openocd_cfg}\" &"
  #OPENOCD_COMMAND="$OPENOCD_BIN -s tcl -c \"set ESP_RTOS nuttx\" -c \"set ESP32_ONLYCPU 1\" -c \"set ESP_FLASH_SIZE 0\" -f \"${openocd_cfg}\" &"
  OPENOCD_COMMAND="$OPENOCD_BIN -s tcl -c \"set ESP_RTOS nuttx\" -f \"${openocd_cfg}\" &"
  echo "$OPENOCD_COMMAND"
  eval "$OPENOCD_COMMAND"
}

function debug {
  case "${chip}" in
    "esp32" | "esp32s2" | "esp32s3" | "esp32c3")
      # Chip specific binary
      [ -z "$extrabreak" ] && extrabreak_cmd="" || extrabreak_cmd="-ex ${extrabreak}"
      GDB_COMMAND="$GDB_BIN -ex \"target extended-remote :3333\" \"${elf_file}\" -ex \"set remote hardware-watchpoint-limit 2\" -ex \"maintenance flush register-cache\" -ex \"mon reset halt\" -ex \"thb ${thbreak}\" -ex \"tui enable\" ${extrabreak_cmd}"
      # General binary with chip specification in parameter
      #GDB_COMMAND="xtensa-esp-elf-gdb-no-python --mcpu=${MCU} -ex \"target extended-remote :3333\" \"${elf_file}\" -ex \"set remote hardware-watchpoint-limit 2\" -ex \"maintenance flush register-cache\" -ex \"mon reset halt\" -ex \"thb ${thbreak}\" -ex \"tui enable\" -ex \"break ${extrabreak}\""
      echo "$GDB_COMMAND"
      eval "$GDB_COMMAND"
      pkill -f openocd # Kill OpenOCD after GDB exits
      ;;
    # Add more chips as needed
    *)
      echo "Unsupported chip: ${chip}"
      exit 1
      ;;
  esac
}

#flash
attach
debug
