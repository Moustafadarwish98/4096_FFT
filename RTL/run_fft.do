vlib work

vlog \
  convround.sv \
  bimpy.v \
  longbimpy.v \
  original_butterfly.sv \
  qtrstage.sv \
  laststage.sv \
  FFT_stage.sv \
  original_bitreverse.sv \
  FFT_main.sv \
  tb_main.sv

vsim -vopt -voptargs=+acc work.tb_fftmain

do wave.do
run -all
