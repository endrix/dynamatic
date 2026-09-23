// RUN: rm -rf %t && mkdir %t
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n sitofp_l3 -o %t/sitofp_l3.vhd -t sitofp -p latency=3 bitwidth=32 'extra_signals={}'
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n uitofp_l1 -o %t/uitofp_l1.vhd -t uitofp -p latency=1 bitwidth=32 'extra_signals={}'
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n fptosi_l0 -o %t/fptosi_l0.vhd -t fptosi -p latency=0 bitwidth=32 'extra_signals={}'
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n fptosi_l5 -o %t/fptosi_l5.vhd -t fptosi -p latency=5 bitwidth=32 'extra_signals={}'
// RUN: FileCheck %s -input-file %t/sitofp_l3.vhd --check-prefix=L3
// RUN: FileCheck %s -input-file %t/uitofp_l1.vhd --check-prefix=L1
// RUN: FileCheck %s -input-file %t/fptosi_l0.vhd --check-prefix=L0
// RUN: FileCheck %s -input-file %t/fptosi_l5.vhd --check-prefix=L5

// The converters delay their data by the unit's latency, the depth of the
// valid propagation buffer, rather than by five stages whatever the latency
// (the Vitis IP's, copied). Five was right only at LATENCY=5; at any other
// the data and the valid left on different cycles.

// L3: entity sitofp_l3_valid_buffer is
// L3: type REG_VALID is array (0 to 3 - 1) of std_logic;
// L3: type delay_stages_t is array (0 to 3 - 1) of std_logic_vector(32 - 1 downto 0);
// L3: outs <= delay_stages(3 - 1);
// L3: delay_stages(0) <= converted;

// L1: entity uitofp_l1_valid_buffer is
// L1: type delay_stages_t is array (0 to 1 - 1) of std_logic_vector(32 - 1 downto 0);
// L1: outs <= delay_stages(1 - 1);

// L0-NOT: valid_buffer
// L0-NOT: delay_stages
// L0: outs <= converted;
// L0: outs_valid <= ins_valid;

// L5: type REG_VALID is array (0 to 5 - 1) of std_logic;
// L5: type delay_stages_t is array (0 to 5 - 1) of std_logic_vector(32 - 1 downto 0);
// L5: outs <= delay_stages(5 - 1);
