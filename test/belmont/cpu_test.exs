defmodule Belmont.CPUTest do
  use ExUnit.Case
  alias Belmont.CPU
  alias Belmont.FakeROM
  alias Belmont.Memory
  alias Belmont.Cartridge

  describe "registers" do
    setup do: {:ok, flags: [:carry, :zero, :interrupt, :overflow, :negative]}

    test "The flag register should be able to have flags set on it" do
      cpu =
        %CPU{}
        |> CPU.set_flag(:zero)
        |> CPU.set_flag(:negative)
        |> CPU.set_flag(:interrupt)

      assert CPU.flag_set?(cpu, :zero)
      assert CPU.flag_set?(cpu, :negative)
      assert CPU.flag_set?(cpu, :interrupt)
      assert !CPU.flag_set?(cpu, :carry)
      assert !CPU.flag_set?(cpu, :overflow)
    end

    test "the flag register should be able to have flags unset", %{flags: flags} do
      cpu = %CPU{registers: %{p: 0xFF}}

      # all flags should be set
      for flag <- flags do
        assert CPU.flag_set?(cpu, flag)
      end

      cpu =
        cpu
        |> CPU.unset_flag(:zero)
        |> CPU.unset_flag(:carry)

      assert !CPU.flag_set?(cpu, :zero)
      assert CPU.flag_set?(cpu, :negative)
      assert CPU.flag_set?(cpu, :interrupt)
      assert !CPU.flag_set?(cpu, :carry)
      assert CPU.flag_set?(cpu, :overflow)
    end

    test "The register bits should be in the right places" do
      assert CPU.flag_set?(%CPU{registers: %{p: 0x01}}, :carry)
      assert CPU.flag_set?(%CPU{registers: %{p: 0x02}}, :zero)
      assert CPU.flag_set?(%CPU{registers: %{p: 0x04}}, :interrupt)
      assert CPU.flag_set?(%CPU{registers: %{p: 0x40}}, :overflow)
      assert CPU.flag_set?(%CPU{registers: %{p: 0x80}}, :negative)
    end

    test "sets a general purpose register" do
      cpu =
        %CPU{}
        |> CPU.set_register(:a, 0x10)
        |> CPU.set_register(:x, 0xF1)
        |> CPU.set_register(:y, 0xA2)

      assert cpu.registers.a == 0x10
      assert cpu.registers.x == 0xF1
      assert cpu.registers.y == 0xA2
    end

    test "set_flag_with_test will either set or unset the flag based on the test byte" do
      cpu =
        %CPU{}
        |> CPU.set_flag_with_test(:zero, 0x00)
        |> CPU.set_flag_with_test(:negative, 0b00000000)
        |> CPU.set_flag_with_test(:overflow, 0b00000000)

      assert CPU.flag_set?(cpu, :zero)
      assert !CPU.flag_set?(cpu, :overflow)
      assert !CPU.flag_set?(cpu, :negative)

      cpu =
        %CPU{}
        |> CPU.set_flag_with_test(:zero, 0x01)
        |> CPU.set_flag_with_test(:negative, 0b10000000)
        |> CPU.set_flag_with_test(:overflow, 0b01000000)

      assert !CPU.flag_set?(cpu, :zero)
      assert CPU.flag_set?(cpu, :negative)
      assert CPU.flag_set?(cpu, :overflow)
    end
  end

  describe "The stack" do
    setup do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0x4C],
            [bank: 0, location: 0x0001, value: 0xF5],
            [bank: 0, location: 0x0002, value: 0xC5]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)

      {:ok, cpu: cpu}
    end

    test "A byte can be pushed", %{cpu: cpu} do
      cpu = CPU.push_byte_onto_stack(cpu, 0x31)
      assert Memory.read_byte(cpu.memory, 0x1FD) == 0x31
      assert cpu.stack_pointer == 0xFC
    end

    test "A word can be pushed", %{cpu: cpu} do
      cpu = CPU.push_word_onto_stack(cpu, 0xC5D1)
      assert Memory.read_byte(cpu.memory, 0x1FD) == 0xC5
      assert Memory.read_byte(cpu.memory, 0x1FC) == 0xD1
      assert cpu.stack_pointer == 0xFB
    end

    test "A byte can be popped off", %{cpu: cpu} do
      assert {cpu, 0x31} =
               CPU.push_byte_onto_stack(cpu, 0x31)
               |> CPU.pop_byte_off_stack()

      assert cpu.stack_pointer == 0xFD
    end
  end

  describe "logical_op/3" do
    setup do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0x29],
            [bank: 0, location: 0x0001, value: 0xEF]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)
        |> CPU.set_register(:a, 0xAB)

      {:ok, cpu: cpu}
    end

    test "and the accumulator with a byte from memory", %{cpu: cpu} do
      cpu = CPU.logical_op(cpu, :immediate, :and)
      assert cpu.registers.a == 0xAB
    end

    test "or the accumulator with a byte from memory", %{cpu: cpu} do
      cpu = CPU.logical_op(cpu, :immediate, :or)
      assert cpu.registers.a == 0xEF
    end
  end

  describe "jmp/2" do
    test "jumps to the location read in memory" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0x4C],
            [bank: 0, location: 0x0001, value: 0xF5],
            [bank: 0, location: 0x0002, value: 0xC5]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)
        |> CPU.jmp(:absolute)

      assert cpu.program_counter == 0xC5F5
      assert cpu.cycle_count == 3
    end
  end

  describe "asl/2" do
    test "shift left" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0x4A]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> CPU.set_register(:a, 0x02)
        |> Map.put(:program_counter, 0x8000)
        |> CPU.asl(:accumulator)

      assert cpu.registers.a == 0x04
    end
  end

  describe "lsr/2" do
    test "shift right" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0x4A]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> CPU.set_register(:a, 0xAA)
        |> Map.put(:program_counter, 0x8000)
        |> CPU.lsr(:accumulator)

      assert cpu.registers.a == 0x55
    end
  end

  describe "ror/2" do
    test "rotate accumulator right" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0x6A]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> CPU.set_register(:a, 0x01)
        |> CPU.set_register(:p, 0x65)
        |> Map.put(:program_counter, 0x8000)
        |> CPU.ror(:accumulator)

      assert cpu.registers.a == 0x80
    end
  end

  describe "rol/2" do
    test "rotate accumulator right" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0x6A]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> CPU.set_register(:a, 0x01)
        |> CPU.set_register(:p, 0x65)
        |> Map.put(:program_counter, 0x8000)
        |> CPU.rol(:accumulator)

      assert cpu.registers.a == 0x03
    end
  end

  describe "bit/2" do
    setup do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0x24],
            [bank: 0, location: 0x0001, value: 0xFF],
            [bank: 0, location: 0x0002, value: 0x00]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)

      {:ok, cpu: cpu}
    end

    test "sets negative and overflow flags", %{cpu: cpu} do
      mem = Memory.write_byte(cpu.memory, 0x00FF, 0xFF)

      cpu =
        cpu
        |> CPU.set_register(:a, 0xFF)
        |> Map.put(:memory, mem)
        |> CPU.bit(:zero_page)

      assert CPU.flag_set?(cpu, :negative)
      assert CPU.flag_set?(cpu, :overflow)
      assert !CPU.flag_set?(cpu, :zero)
    end

    test "sets the zero flag", %{cpu: cpu} do
      mem = Memory.write_byte(cpu.memory, 0x00FF, 0xFF)

      cpu =
        cpu
        |> CPU.set_register(:a, 0x00)
        |> Map.put(:memory, mem)
        |> CPU.bit(:zero_page)

      assert CPU.flag_set?(cpu, :zero)
    end
  end

  describe "increment_register/2" do
    test "increments the given register by 1" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0xC8]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> CPU.set_register(:y, 255)
        |> Map.put(:program_counter, 0x8000)
        |> CPU.increment_register(:y)

      assert cpu.registers.y == 0
    end
  end

  describe "decrement_register/2" do
    test "decrements the given register by 1" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0xCA]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> CPU.set_register(:y, 0)
        |> Map.put(:program_counter, 0x8000)
        |> CPU.decrement_register(:y)

      assert cpu.registers.y == 255
    end
  end

  describe "compare/3" do
    setup do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0xC9],
            [bank: 0, location: 0x0001, value: 0x35]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)

      {:ok, cpu: cpu}
    end

    test "sets the carry flag", %{cpu: cpu} do
      cpu =
        cpu
        |> CPU.set_register(:a, 0x37)
        |> CPU.compare(:immediate, :a)

      assert CPU.flag_set?(cpu, :carry)
    end

    test "sets the zero flag", %{cpu: cpu} do
      cpu =
        cpu
        |> CPU.set_register(:a, 0x35)
        |> CPU.compare(:immediate, :a)

      assert CPU.flag_set?(cpu, :zero)
    end
  end

  describe "load_register/2" do
    setup do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0xA2],
            [bank: 0, location: 0x0001, value: 0x75],
            [bank: 0, location: 0x0002, value: 0xA2],
            [bank: 0, location: 0x0003, value: 0xFF],
            [bank: 0, location: 0x0004, value: 0xA2],
            [bank: 0, location: 0x0005, value: 0x00]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)

      {:ok, cpu: cpu}
    end

    test "reads a value from memory and sets it to the x register", %{cpu: cpu} do
      cpu = CPU.load_register(cpu, :immediate, :x)
      assert cpu.registers.x == 0x75
    end

    test "sets the negative flag", %{cpu: cpu} do
      cpu = Map.put(cpu, :program_counter, 0x8002) |> CPU.load_register(:immediate, :x)
      assert CPU.flag_set?(cpu, :negative) == true
    end

    test "sets the zero flag", %{cpu: cpu} do
      cpu = Map.put(cpu, :program_counter, 0x8004) |> CPU.load_register(:immediate, :x)
      assert CPU.flag_set?(cpu, :zero) == true
    end
  end

  describe "store_register/2" do
    test "stores the x register in memory" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0x86],
            [bank: 0, location: 0x0001, value: 0x00]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)
        |> CPU.set_register(:x, 0x31)
        |> CPU.store_register(:zero_page, :x)

      assert Memory.read_byte(cpu.memory, 0x0000) == 0x31
    end
  end

  describe "transfer_accumulator/2" do
    test "copies a to the register" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0xAA]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> CPU.set_register(:a, 0xEE)
        |> Map.put(:program_counter, 0x8000)
        |> CPU.transfer_accumulator(:a, :y)

      assert cpu.registers.y == 0xEE
    end
  end

  describe "transfer_stack_x/1" do
    test "copies the stack pointer to the x register" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0xBA]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)
        |> CPU.transfer_stack_x()

      assert cpu.registers.x == 0xFD
    end
  end

  describe "transfer_x_stack/1" do
    test "copies the x register to the stack pointer" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0000, value: 0x0A]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> CPU.set_register(:x, 0x33)
        |> Map.put(:program_counter, 0x8000)
        |> CPU.transfer_x_stack()

      assert cpu.stack_pointer == 0x33
    end
  end

  describe "rti/1" do
    test "sets the status register and program counter from stack" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0001, value: 0x40]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> CPU.push_word_onto_stack(0x3355)
        |> CPU.push_byte_onto_stack(0x11)
        |> CPU.set_register(:p, 0x00)
        |> Map.put(:program_counter, 0x8000)
        |> CPU.rti()

      assert cpu.registers.p == 0x21
      assert cpu.program_counter == 0x3355
    end
  end

  describe "jsr/2" do
    test "should push the return point onto the stack and jump to a location" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0001, value: 0x2D],
            [bank: 0, location: 0x0002, value: 0xC7]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)
        |> CPU.jsr(:absolute)

      assert cpu.program_counter == 0xC72D
      assert {cpu, 0x02} = CPU.pop_byte_off_stack(cpu)
      assert {_cpu, 0x80} = CPU.pop_byte_off_stack(cpu)
    end
  end

  describe "rts/1" do
    test "should return to the point pushed onto the stack + 1" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0001, value: 0x60]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)
        |> CPU.push_word_onto_stack(0xC5FF)
        |> CPU.rts()

      assert cpu.program_counter == 0xC600
      assert cpu.stack_pointer == 0xFD
    end
  end

  describe "php/1" do
    test "should push the flag register onto the stack" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0001, value: 0x08]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)
        |> CPU.set_register(:p, 0xFF)
        |> CPU.php()

      assert cpu.stack_pointer == 0xFC
      {_cpu, value} = CPU.pop_byte_off_stack(cpu)
      assert value == 0xFF
    end
  end

  describe "pla/1" do
    test "should pop a byte off the stack and store it in the accumulator" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0001, value: 0x08]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)
        |> CPU.set_register(:p, 0xFF)
        |> CPU.php()
        |> CPU.pla()

      assert cpu.stack_pointer == 0xFD
      assert cpu.registers.a == 0xFF
    end
  end

  describe "pha/1" do
    test "pushes accumulator onto the stack" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0001, value: 0x08]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)
        |> CPU.set_register(:a, 0xFF)
        |> CPU.pha()

      assert cpu.stack_pointer == 0xFC
      {_cpu, value} = CPU.pop_byte_off_stack(cpu)
      assert value == 0xFF
    end
  end

  describe "plp/1" do
    test "pop byte off stack and sets it on the status register" do
      cpu =
        FakeROM.rom(
          prg_rom_data_override: [
            [bank: 0, location: 0x0001, value: 0x28]
          ]
        )
        |> Cartridge.parse_rom_contents!()
        |> Memory.new()
        |> CPU.new()
        |> Map.put(:program_counter, 0x8000)
        |> CPU.set_register(:p, 0xFF)
        |> CPU.php()
        |> CPU.pla()

      assert cpu.stack_pointer == 0xFD
      assert cpu.registers.p == 0xFD
    end
  end
end
