onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group Global /tb_fftmain/i_clk
add wave -noupdate -group Global /tb_fftmain/i_reset
add wave -noupdate -group Global /tb_fftmain/i_clk_enable
add wave -noupdate -group TB /tb_fftmain/i_sample
add wave -noupdate -group TB /tb_fftmain/o_result
add wave -noupdate -group TB /tb_fftmain/o_sync
add wave -noupdate -group TB /tb_fftmain/out_count
add wave -noupdate -group TB /tb_fftmain/fout
add wave -noupdate -group TB /tb_fftmain/frame_active
add wave -noupdate -group TB /tb_fftmain/o_real
add wave -noupdate -group TB /tb_fftmain/o_imag
add wave -noupdate -group TB /tb_fftmain/mag
add wave -noupdate -group TB /tb_fftmain/k
add wave -noupdate -group TB /tb_fftmain/bin
add wave -noupdate -group TB /tb_fftmain/core_latency
add wave -noupdate -group TB /tb_fftmain/br_latency
add wave -noupdate -group TB /tb_fftmain/total_latency
add wave -noupdate -group TB /tb_fftmain/core_counter
add wave -noupdate -group TB /tb_fftmain/br_counter
add wave -noupdate -group TB /tb_fftmain/core_measured
add wave -noupdate -group TB /tb_fftmain/br_measured
add wave -noupdate -group Main /tb_fftmain/dut/i_sample
add wave -noupdate -group Main /tb_fftmain/dut/o_result
add wave -noupdate -group Main /tb_fftmain/dut/o_sync
add wave -noupdate -group Main /tb_fftmain/dut/br_sync
add wave -noupdate -group Main /tb_fftmain/dut/br_result
add wave -noupdate -group Main /tb_fftmain/dut/w_s4096
add wave -noupdate -group Main /tb_fftmain/dut/w_d4096
add wave -noupdate -group Main /tb_fftmain/dut/w_s2048
add wave -noupdate -group Main /tb_fftmain/dut/w_d2048
add wave -noupdate -group Main /tb_fftmain/dut/w_s1024
add wave -noupdate -group Main /tb_fftmain/dut/w_d1024
add wave -noupdate -group Main /tb_fftmain/dut/w_s512
add wave -noupdate -group Main /tb_fftmain/dut/w_d512
add wave -noupdate -group Main /tb_fftmain/dut/w_s256
add wave -noupdate -group Main /tb_fftmain/dut/w_d256
add wave -noupdate -group Main /tb_fftmain/dut/w_s128
add wave -noupdate -group Main /tb_fftmain/dut/w_d128
add wave -noupdate -group Main /tb_fftmain/dut/w_s64
add wave -noupdate -group Main /tb_fftmain/dut/w_d64
add wave -noupdate -group Main /tb_fftmain/dut/w_s32
add wave -noupdate -group Main /tb_fftmain/dut/w_d32
add wave -noupdate -group Main /tb_fftmain/dut/w_s16
add wave -noupdate -group Main /tb_fftmain/dut/w_d16
add wave -noupdate -group Main /tb_fftmain/dut/w_s8
add wave -noupdate -group Main /tb_fftmain/dut/w_d8
add wave -noupdate -group Main /tb_fftmain/dut/w_s4
add wave -noupdate -group Main /tb_fftmain/dut/w_d4
add wave -noupdate -group Main /tb_fftmain/dut/w_s2
add wave -noupdate -group Main /tb_fftmain/dut/w_d2
add wave -noupdate -group Main /tb_fftmain/dut/br_start
add wave -noupdate -group Main /tb_fftmain/dut/r_br_started
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/i_sync
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/i_data
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/o_data
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/o_sync
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/wait_for_sync
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/ib_a
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/ib_b
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/ib_c
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/ib_sync
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/b_started
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/ob_sync
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/ob_a
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/ob_b
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/cmem
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/iaddr
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/imem
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/oaddr
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/omem
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/nxt_oaddr
add wave -noupdate -expand -group Stage4096 /tb_fftmain/dut/stage_4096/pre_ovalue
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/i_sync
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/i_data
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/o_data
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/o_sync
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/wait_for_sync
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/ib_a
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/ib_b
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/ib_c
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/ib_sync
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/b_started
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/ob_sync
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/ob_a
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/ob_b
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/cmem
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/iaddr
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/imem
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/oaddr
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/omem
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/nxt_oaddr
add wave -noupdate -group Stage2048 /tb_fftmain/dut/stage_2048/pre_ovalue
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/i_sync
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/i_data
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/o_data
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/o_sync
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/wait_for_sync
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/ib_a
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/ib_b
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/ib_c
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/ib_sync
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/b_started
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/ob_sync
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/ob_a
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/ob_b
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/cmem
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/iaddr
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/imem
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/oaddr
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/omem
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/nxt_oaddr
add wave -noupdate -group Stage1024 /tb_fftmain/dut/stage_1024/pre_ovalue
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/i_sync
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/i_data
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/o_data
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/o_sync
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/wait_for_sync
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/ib_a
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/ib_b
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/ib_c
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/ib_sync
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/b_started
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/ob_sync
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/ob_a
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/ob_b
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/cmem
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/iaddr
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/imem
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/oaddr
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/omem
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/nxt_oaddr
add wave -noupdate -group Stage512 /tb_fftmain/dut/stage_512/pre_ovalue
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/i_sync
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/i_data
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/o_data
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/o_sync
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/wait_for_sync
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/ib_a
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/ib_b
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/ib_c
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/ib_sync
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/b_started
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/ob_sync
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/ob_a
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/ob_b
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/cmem
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/iaddr
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/imem
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/oaddr
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/omem
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/nxt_oaddr
add wave -noupdate -group Stage256 /tb_fftmain/dut/stage_256/pre_ovalue
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/i_sync
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/i_data
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/o_data
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/o_sync
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/wait_for_sync
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/ib_a
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/ib_b
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/ib_c
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/ib_sync
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/b_started
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/ob_sync
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/ob_a
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/ob_b
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/cmem
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/iaddr
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/imem
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/oaddr
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/omem
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/nxt_oaddr
add wave -noupdate -group Stage128 /tb_fftmain/dut/stage_128/pre_ovalue
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/i_sync
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/i_data
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/o_data
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/o_sync
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/wait_for_sync
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/ib_a
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/ib_b
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/ib_c
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/ib_sync
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/b_started
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/ob_sync
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/ob_a
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/ob_b
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/cmem
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/iaddr
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/imem
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/oaddr
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/omem
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/nxt_oaddr
add wave -noupdate -group Stage64 /tb_fftmain/dut/stage_64/pre_ovalue
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/i_sync
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/i_data
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/o_data
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/o_sync
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/wait_for_sync
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/ib_a
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/ib_b
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/ib_c
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/ib_sync
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/b_started
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/ob_sync
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/ob_a
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/ob_b
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/cmem
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/iaddr
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/imem
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/oaddr
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/omem
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/nxt_oaddr
add wave -noupdate -group Stage32 /tb_fftmain/dut/stage_32/pre_ovalue
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/i_sync
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/i_data
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/o_data
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/o_sync
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/wait_for_sync
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/ib_a
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/ib_b
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/ib_c
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/ib_sync
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/b_started
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/ob_sync
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/ob_a
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/ob_b
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/cmem
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/iaddr
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/imem
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/oaddr
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/omem
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/nxt_oaddr
add wave -noupdate -group Stage16 /tb_fftmain/dut/stage_16/pre_ovalue
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/i_sync
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/i_data
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/o_data
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/o_sync
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/wait_for_sync
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/ib_a
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/ib_b
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/ib_c
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/ib_sync
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/b_started
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/ob_sync
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/ob_a
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/ob_b
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/cmem
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/iaddr
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/imem
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/oaddr
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/omem
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/nxt_oaddr
add wave -noupdate -group Stage8 /tb_fftmain/dut/stage_8/pre_ovalue
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/i_sync
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/i_data
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/o_data
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/o_sync
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/wait_for_sync
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/pipeline
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/sum_r
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/sum_i
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/diff_r
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/diff_i
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/ob_a
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/ob_b
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/ob_b_r
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/ob_b_i
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/iaddr
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/imem
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/imem_r
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/imem_i
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/i_data_r
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/i_data_i
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/omem
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/rnd_sum_r
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/rnd_sum_i
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/rnd_diff_r
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/rnd_diff_i
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/n_rnd_diff_r
add wave -noupdate -group Stage4 /tb_fftmain/dut/stage_4/n_rnd_diff_i
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/i_sync
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/i_val
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/o_val
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/o_sync
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/m_r
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/m_i
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/i_r
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/i_i
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/rnd_r
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/rnd_i
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/sto_r
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/sto_i
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/wait_for_sync
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/stage
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/sync_pipe
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/o_r
add wave -noupdate -group laststage /tb_fftmain/dut/stage_2/o_i
add wave -noupdate -group BitReverse /tb_fftmain/dut/revstage/in_reset
add wave -noupdate -group BitReverse /tb_fftmain/dut/revstage/i_in
add wave -noupdate -group BitReverse /tb_fftmain/dut/revstage/o_out
add wave -noupdate -group BitReverse /tb_fftmain/dut/revstage/o_sync
add wave -noupdate -group BitReverse /tb_fftmain/dut/revstage/wraddr
add wave -noupdate -group BitReverse /tb_fftmain/dut/revstage/rdaddr
add wave -noupdate -group BitReverse /tb_fftmain/dut/revstage/brmem
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/MXMPYBITS
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/MPYDELAY
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/LGDELAY
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/AUXLEN
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/i_coef
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/i_left
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/i_right
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/i_aux
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/o_left
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/o_right
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/o_aux
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_left
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_right
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_coef
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_coef_2
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_left_r
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_left_i
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_right_r
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_right_i
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_sum_r
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_sum_i
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_dif_r
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/r_dif_i
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/fifo_addr
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/fifo_read_addr
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/fifo_left
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/ir_coef_r
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/ir_coef_i
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/p_one
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/p_two
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/p_three
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/fifo_i
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/fifo_r
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/fifo_read
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/mpy_r
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/mpy_i
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/rnd_left_r
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/rnd_left_i
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/rnd_right_r
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/rnd_right_i
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/left_sr
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/left_si
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/aux_pipeline
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/p3c_in
add wave -noupdate -group BFLY4096 /tb_fftmain/dut/stage_4096/bfly/p3d_in
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {124724050 ps} {124725050 ps}
