defmodule Belmont.CPU do
  # TODO: Are page_crossed ifs correct? I think I'm missing some on indirect_indexed...
  @moduledoc """
  The cpu represents everything we need to emulate the NES CPU. The NES' CPU is a variation of the 6502
  processor that runs at 1.79 MHz (PAL regions is 1.66 MHz). One of the differences between the NES' CPU and the standard
  MOS6502 is that the NES does not have a decimal mode, saving us a bit of work. The CPU is little endian.

  The NES CPU has 4 work registers (excluding program_counter and the stack_pointer). All 4 registers
  are a byte wide.

  * :a - The accumulator register.
  * :x - A general purpose index register.
  * :y - A general purpose index register.
  * :p - The status register, used to store flags.
  """

  use Bitwise
  alias Belmont.CPU.AddressingMode
  alias Belmont.Memory
  alias Belmont.Hexstr

  @typedoc """
  Defines the CPU state.
  * :program_counter - A 16-bit register that points to the current instruction to be processed by the CPU.
  * :stack_pointer - An 8-bit register that points at the *TOP* of the stack. The stack is located from $0100-01FF,
    so the stack pointer works as an offset pointing between the beginning and ending memory locations.
    The stack is top-down, so the stack pointer is decremented when a byte is pushed onto the stack.
  * :registers - CPU registers.
  * :cycle_count - Counts the number of CPU cycles used during execution. This is our primary mechanism for pacing.
  * :memory - Memory struct.
  """
  @type t :: %__MODULE__{
          program_counter: integer(),
          stack_pointer: byte(),
          registers: %{a: byte(), x: byte(), y: byte(), p: byte()},
          cycle_count: integer(),
          memory: Belmont.Memory.t()
        }

  defstruct program_counter: 0x0000,
            stack_pointer: 0xFD,
            registers: %{a: 0x00, x: 0x00, y: 0x00, p: 0x24},
            cycle_count: 0,
            memory: %Belmont.Memory{}

  # Defines all of the possible flags available to be set on the status register and the bit
  # where they are located. Bits 3-5 of the status flag are not used in the NES for flags, but
  # can be used to serve other purposes.
  @flags %{
    carry: 1 <<< 0,
    zero: 1 <<< 1,
    interrupt: 1 <<< 2,
    decimal: 1 <<< 3,
    unused_1: 1 <<< 4,
    unused_2: 1 <<< 5,
    overflow: 1 <<< 6,
    negative: 1 <<< 7
  }

  @doc """
  Creates a new CPU
  """
  @spec new(Belmont.Memory.t()) :: t()
  def new(memory) do
    %__MODULE__{memory: memory}
  end

  @doc """
  Test if a given flag is set on the flag register.
  """
  @spec flag_set?(t(), atom()) :: boolean()
  def flag_set?(cpu, flag) do
    band(cpu.registers.p, @flags[flag]) != 0
  end

  @doc """
  Set the given flag on the flag register.
  """
  @spec set_flag(t(), atom()) :: t()
  def set_flag(cpu, flag) do
    registers = %{cpu.registers | p: bor(cpu.registers.p, @flags[flag])}
    %{cpu | registers: registers}
  end

  @doc """
  Set or unset the given flag using a test byte to determine the flag's state
  """
  def set_flag_with_test(cpu, :zero, test_byte) do
    if test_byte == 0, do: set_flag(cpu, :zero), else: unset_flag(cpu, :zero)
  end

  def set_flag_with_test(cpu, :negative, test_byte) do
    if band(test_byte, 0x80) != 0, do: set_flag(cpu, :negative), else: unset_flag(cpu, :negative)
  end

  def set_flag_with_test(cpu, :overflow, test_byte) do
    if band(test_byte, 0x70) != 0, do: set_flag(cpu, :overflow), else: unset_flag(cpu, :overflow)
  end

  @doc """
  Unset the given flag on the status register.
  """
  @spec unset_flag(t(), atom()) :: t()
  def unset_flag(cpu, flag) do
    registers = %{cpu.registers | p: cpu.registers.p &&& bnot(@flags[flag])}
    %{cpu | registers: registers}
  end

  @doc """
  Set a register to a specific value.
  """
  @spec set_register(t(), atom(), byte()) :: t()
  def set_register(cpu, register_key, value) when value <= 0xFF and value >= 0 do
    registers = Map.put(cpu.registers, register_key, value)
    %{cpu | registers: registers}
  end

  @doc """
  Pushes a byte onto the stack.
  """
  @spec push_byte_onto_stack(t(), byte()) :: t()
  def push_byte_onto_stack(cpu, byte) do
    memory = Memory.write_byte(cpu.memory, 0x100 + cpu.stack_pointer, byte)
    # simulate byte overflow
    wrapped_stack_pointer = Integer.mod(cpu.stack_pointer - 1, 256)

    %{cpu | memory: memory, stack_pointer: wrapped_stack_pointer}
  end

  @doc """
  Pushes a word onto a stack by writing each byte individually.
  """
  @spec push_word_onto_stack(t(), integer()) :: t()
  def push_word_onto_stack(cpu, word) do
    <<high_byte, low_byte>> = <<word::size(16)>>

    cpu
    |> push_byte_onto_stack(high_byte)
    |> push_byte_onto_stack(low_byte)
  end

  @doc """
  Pops a byte off of the stack.
  """
  @spec pop_byte_off_stack(t()) :: {t(), byte()}
  def pop_byte_off_stack(cpu) do
    wrapped_stack_pointer = Integer.mod(cpu.stack_pointer + 1, 256)
    byte = Memory.read_byte(cpu.memory, 0x100 + wrapped_stack_pointer)
    {%{cpu | stack_pointer: wrapped_stack_pointer}, byte}
  end

  @doc """
  Process the current instruction pointed at by the program counter.
  """
  @spec step(t()) :: t()
  def step(cpu) do
    opcode = Memory.read_byte(cpu.memory, cpu.program_counter)
    Belmont.CPU.Instructions.execute(cpu, opcode)
    # |> step()
  end

  # Logs an instruction and the current state of the CPU using a format that can be compared
  # against output from nestest logs. We aren't logging the full mnemonic of the instruction,
  # because it isn't needed.
  def log_state(cpu, opcode, mnemonic, operand_size) do
    pc = Hexstr.hex(cpu.program_counter, 4)
    op = Hexstr.hex(opcode, 2)
    stack_pointer = Hexstr.hex(cpu.stack_pointer, 2)

    operands =
      case operand_size do
        :byte ->
          Belmont.Memory.read_byte(cpu.memory, cpu.program_counter + 1) |> Hexstr.hex(2)

        :word ->
          low_byte = Belmont.Memory.read_byte(cpu.memory, cpu.program_counter + 1) |> Hexstr.hex(2)
          high_byte = Belmont.Memory.read_byte(cpu.memory, cpu.program_counter + 2) |> Hexstr.hex(2)
          "#{low_byte} #{high_byte}"

        _ ->
          ""
      end

    operands = String.pad_trailing(operands, 6, " ")

    # flags
    a = Hexstr.hex(cpu.registers[:a], 2)
    x = Hexstr.hex(cpu.registers[:x], 2)
    y = Hexstr.hex(cpu.registers[:y], 2)
    p = Hexstr.hex(cpu.registers[:p], 2)
    flags = "A:#{a} X:#{x} Y:#{y} P:#{p}"

    mnemonic = String.pad_trailing(mnemonic, 31, " ")

    cyc =
      Integer.mod(cpu.cycle_count * 3, 341)
      |> Integer.to_string()
      |> String.pad_leading(3, " ")

    "#{pc}  #{op} #{operands} #{mnemonic} #{flags} SP:#{stack_pointer} CYC:#{cyc}"
    |> String.upcase()
  end

  # TODO: remove me: temporary function to help debug status differences
  def debug_flag_log(belmont, nestest) do
    p = 15

    (String.pad_trailing("", p) <>
       String.pad_trailing("belmont #{Hexstr.hex(belmont)}", p) <>
       String.pad_trailing("nestest #{Hexstr.hex(nestest)}", p))
    |> IO.puts()

    Enum.each(@flags, fn {key, flag} ->
      belmont_set = band(belmont, flag) != 0
      nestest_set = band(nestest, flag) != 0

      (String.pad_trailing(Atom.to_string(key), p) <>
         String.pad_trailing(inspect(belmont_set), p) <>
         String.pad_trailing(inspect(nestest_set), p))
      |> IO.puts()
    end)
  end

  def nop(cpu, addressing_mode) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)

    {pc, cycle} =
      case addressing_mode do
        :implied -> {1, 2}
        :immediate -> {2, 2}
        :zero_page -> {2, 3}
        :absolute -> {3, 4}
        :absolute_x -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :absolute_y -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :zero_page_x -> {2, 4}
      end

    %{cpu | program_counter: cpu.program_counter + pc, cycle_count: cpu.cycle_count + cycle}
  end

  @doc """
  set a flag to 1
  """
  def set_flag_op(cpu, flag) do
    cpu
    |> set_flag(flag)
    |> Map.put(:program_counter, cpu.program_counter + 1)
    |> Map.put(:cycle_count, cpu.cycle_count + 2)
  end

  @doc """
  set a flag to 0
  """
  def unset_flag_op(cpu, flag) do
    cpu
    |> unset_flag(flag)
    |> Map.put(:program_counter, cpu.program_counter + 1)
    |> Map.put(:cycle_count, cpu.cycle_count + 2)
  end

  @doc """
  adds the contents of a memory location to the accumulator together with the carry bit
  """
  def adc(cpu, addressing_mode) do
    acc = cpu.registers.a
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)
    val = byte + acc + (cpu.registers.p &&& 0x01)

    overflow = (Bitwise.bxor(acc, byte) &&& 0x80) == 0x00 && (Bitwise.bxor(acc, val) &&& 0x80) != 0x00

    {pc, cycle} =
      case addressing_mode do
        :immediate -> {2, 2}
        :zero_page -> {2, 3}
        :zero_page_x -> {2, 4}
        :absolute -> {3, 4}
        :absolute_x -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :absolute_y -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :indexed_indirect -> {2, 6}
        :indirect_indexed -> if byte_address.page_crossed, do: {2, 6}, else: {2, 5}
      end

    wrapped_val = rem(val, 256)

    cpu =
      cpu
      |> set_register(:a, wrapped_val)
      |> set_flag_with_test(:zero, wrapped_val)
      |> set_flag_with_test(:negative, wrapped_val)
      |> Map.put(:program_counter, cpu.program_counter + pc)
      |> Map.put(:cycle_count, cpu.cycle_count + cycle)

    cpu = if overflow, do: set_flag(cpu, :overflow), else: unset_flag(cpu, :overflow)
    if val > 0xFF, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)
  end

  @doc """
  subtracts the contents of a memory location from the accumulator together with the carry bit
  """
  def sbc(cpu, addressing_mode) do
    acc = cpu.registers.a
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)
    val = acc - byte - 1 + (cpu.registers.p &&& 0x01)

    overflow = (Bitwise.bxor(acc, byte) &&& 0x80) != 0x00 && (Bitwise.bxor(acc, val) &&& 0x80) != 0x00

    {pc, cycle} =
      case addressing_mode do
        :immediate -> {2, 2}
        :zero_page -> {2, 3}
        :zero_page_x -> {2, 4}
        :absolute -> {3, 4}
        :absolute_x -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :absolute_y -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :indexed_indirect -> {2, 6}
        :indirect_indexed -> if byte_address.page_crossed, do: {2, 6}, else: {2, 5}
      end

    wrapped_val = if val < 0, do: 256 + val, else: val

    cpu =
      cpu
      |> set_register(:a, wrapped_val)
      |> set_flag_with_test(:zero, wrapped_val)
      |> set_flag_with_test(:negative, wrapped_val)
      |> Map.put(:program_counter, cpu.program_counter + pc)
      |> Map.put(:cycle_count, cpu.cycle_count + cycle)

    cpu = if overflow, do: set_flag(cpu, :overflow), else: unset_flag(cpu, :overflow)
    if val >= 0, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)
  end

  @doc """
  performs a logical operation on a byte in memory with the accumulator
  """
  def logical_op(cpu, addressing_mode, op) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)

    val =
      case op do
        :and -> cpu.registers.a &&& byte
        :or -> bor(cpu.registers.a, byte)
        :eor -> bxor(cpu.registers.a, byte)
      end

    {pc, cycle} =
      case addressing_mode do
        :immediate -> {2, 2}
        :zero_page -> {2, 3}
        :zero_page_x -> {2, 4}
        :absolute -> {3, 4}
        :absolute_x -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :absolute_y -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :indexed_indirect -> {2, 6}
        :indirect_indexed -> if byte_address.page_crossed, do: {2, 6}, else: {2, 5}
      end

    cpu
    |> set_register(:a, val)
    |> set_flag_with_test(:zero, val)
    |> set_flag_with_test(:negative, val)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
  end

  @doc """
  read a word and set the program counter to that value
  """
  def jmp(cpu, addressing_mode) do
    {pc, cycles} =
      case addressing_mode do
        :absolute ->
          address = AddressingMode.get_address(:absolute, cpu)
          {address.address, 3}

        :indirect ->
          address = AddressingMode.get_address(:indirect_with_jmp_bug, cpu)
          {address.address, 5}
      end

    %{cpu | program_counter: pc, cycle_count: cpu.cycle_count + cycles}
  end

  @doc """
  Arithmetic shift accumulator or byte left
  """
  def asl(cpu, :accumulator) do
    byte = cpu.registers.a
    {pc, cycle} = {1, 2}

    res = Bitwise.bsl(byte, 1) |> Bitwise.band(0xFF)
    cpu = if band(byte, @flags[:negative]) != 0, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)

    cpu
    |> set_flag_with_test(:zero, res)
    |> set_flag_with_test(:negative, res)
    |> set_register(:a, res)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
  end

  def asl(cpu, addressing_mode) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)

    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        _ -> {0, 0}
      end

    res = Bitwise.bsl(byte, 1) |> Bitwise.band(0xFF)
    cpu = if band(byte, @flags[:negative]) != 0, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)
    memory = Memory.write_byte(cpu.memory, byte_address.address, res)

    cpu
    |> set_flag_with_test(:zero, res)
    |> set_flag_with_test(:negative, res)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
    |> Map.put(:memory, memory)
  end

  @doc """
  illegal opcode that implements ASL + ORA
  """
  def slo(cpu, addressing_mode) do
    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        :absolute_y -> {3, 7}
        :indexed_indirect -> {2, 8}
        :indirect_indexed -> {2, 8}
      end

    orig_pc = cpu.program_counter
    orig_cycle = cpu.cycle_count
    pc = orig_pc + pc
    cycle = orig_cycle + cycle

    cpu
    |> asl(addressing_mode)
    |> Map.put(:program_counter, orig_pc)
    |> Map.put(:cycle_count, orig_cycle)
    |> logical_op(addressing_mode, :or)
    |> Map.put(:program_counter, pc)
    |> Map.put(:cycle_count, cycle)
  end

  @doc """
  Logical shift accumulator or byte right
  """
  def lsr(cpu, :accumulator) do
    byte = cpu.registers.a
    {pc, cycle} = {1, 2}

    res = Bitwise.bsr(byte, 1)
    cpu = if band(byte, @flags[:carry]) != 0, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)

    cpu
    |> set_flag_with_test(:zero, res)
    |> unset_flag(:negative)
    |> set_register(:a, res)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
  end

  def lsr(cpu, addressing_mode) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)

    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        _ -> {0, 0}
      end

    res = Bitwise.bsr(byte, 1)
    cpu = if band(byte, @flags[:carry]) != 0, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)
    memory = Memory.write_byte(cpu.memory, byte_address.address, res)

    cpu
    |> set_flag_with_test(:zero, res)
    |> unset_flag(:negative)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
    |> Map.put(:memory, memory)
  end

  @doc """
  illegal opcode that performs LSR + EOR
  """
  def sre(cpu, addressing_mode) do
    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        :absolute_y -> {3, 7}
        :indexed_indirect -> {2, 8}
        :indirect_indexed -> {2, 8}
      end

    orig_pc = cpu.program_counter
    orig_cycle = cpu.cycle_count
    pc = orig_pc + pc
    cycle = orig_cycle + cycle

    cpu
    |> lsr(addressing_mode)
    |> Map.put(:program_counter, orig_pc)
    |> Map.put(:cycle_count, orig_cycle)
    |> logical_op(addressing_mode, :eor)
    |> Map.put(:program_counter, pc)
    |> Map.put(:cycle_count, cycle)
  end

  @doc """
  Rotate accumulator or byte right
  """
  def ror(cpu, :accumulator) do
    byte = cpu.registers.a
    {pc, cycle} = {1, 2}

    carry_bit = if flag_set?(cpu, :carry), do: 1, else: 0
    res = byte >>> 1 ||| carry_bit <<< 7
    cpu = if band(byte, @flags[:carry]) != 0, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)

    cpu
    |> set_flag_with_test(:zero, res)
    |> set_flag_with_test(:negative, res)
    |> set_register(:a, res)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
  end

  def ror(cpu, addressing_mode) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)

    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        _ -> {0, 0}
      end

    carry_bit = if flag_set?(cpu, :carry), do: 1, else: 0
    res = byte >>> 1 ||| carry_bit <<< 7
    cpu = if band(byte, @flags[:carry]) != 0, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)
    memory = Memory.write_byte(cpu.memory, byte_address.address, res)

    cpu
    |> set_flag_with_test(:zero, res)
    |> set_flag_with_test(:negative, res)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
    |> Map.put(:memory, memory)
  end

  @doc """
  Illegal instruction that performs ROR + ADC
  """
  def rra(cpu, addressing_mode) do
    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        :absolute_y -> {3, 7}
        :indexed_indirect -> {2, 8}
        :indirect_indexed -> {2, 8}
      end

    orig_pc = cpu.program_counter
    orig_cycle = cpu.cycle_count
    pc = orig_pc + pc
    cycle = orig_cycle + cycle

    cpu
    |> ror(addressing_mode)
    |> Map.put(:program_counter, orig_pc)
    |> Map.put(:cycle_count, orig_cycle)
    |> adc(addressing_mode)
    |> Map.put(:program_counter, pc)
    |> Map.put(:cycle_count, cycle)
  end

  @doc """
  Rotate accumulator or byte left
  """
  def rol(cpu, :accumulator) do
    byte = cpu.registers.a
    {pc, cycle} = {1, 2}

    carry_bit = if flag_set?(cpu, :carry), do: 1, else: 0
    res = rem(byte <<< 1 ||| carry_bit, 256)
    cpu = if band(byte, @flags[:negative]) != 0, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)

    cpu
    |> set_flag_with_test(:zero, res)
    |> set_flag_with_test(:negative, res)
    |> set_register(:a, res)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
  end

  def rol(cpu, addressing_mode) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)

    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        _ -> {0, 0}
      end

    carry_bit = if flag_set?(cpu, :carry), do: 1, else: 0
    res = rem(byte <<< 1 ||| carry_bit, 256)
    cpu = if band(byte, @flags[:negative]) != 0, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)
    memory = Memory.write_byte(cpu.memory, byte_address.address, res)

    cpu
    |> set_flag_with_test(:zero, res)
    |> set_flag_with_test(:negative, res)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
    |> Map.put(:memory, memory)
  end

  @doc """
  illegal opcade that ROL + AND
  """
  def rla(cpu, addressing_mode) do
    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        :absolute_y -> {3, 7}
        :indexed_indirect -> {2, 8}
        :indirect_indexed -> {2, 8}
      end

    orig_pc = cpu.program_counter
    orig_cycle = cpu.cycle_count
    pc = orig_pc + pc
    cycle = orig_cycle + cycle

    cpu
    |> rol(addressing_mode)
    |> Map.put(:program_counter, orig_pc)
    |> Map.put(:cycle_count, orig_cycle)
    |> logical_op(addressing_mode, :and)
    |> Map.put(:program_counter, pc)
    |> Map.put(:cycle_count, cycle)
  end

  @doc """
  test if one or more bits are set
  """
  def bit(cpu, addressing_mode) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)
    res = cpu.registers.a &&& byte

    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 3}
        :absolute -> {3, 4}
      end

    cpu
    |> set_flag_with_test(:zero, res)
    |> set_flag_with_test(:negative, byte)
    |> set_flag_with_test(:overflow, byte)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
  end

  @doc """
  increment the given register by 1
  """
  def increment_register(cpu, reg) do
    val = cpu.registers[reg] + 1
    wrapped_val = rem(val, 256)

    cpu
    |> set_flag_with_test(:negative, wrapped_val)
    |> set_flag_with_test(:zero, wrapped_val)
    |> set_register(reg, wrapped_val)
    |> Map.put(:program_counter, cpu.program_counter + 1)
    |> Map.put(:cycle_count, cpu.cycle_count + 2)
  end

  @doc """
  decrement the given register by 1
  """
  def decrement_register(cpu, reg) do
    val = cpu.registers[reg] - 1
    wrapped_val = if val < 0, do: 256 + val, else: val

    cpu
    |> set_flag_with_test(:negative, wrapped_val)
    |> set_flag_with_test(:zero, wrapped_val)
    |> set_register(reg, wrapped_val)
    |> Map.put(:program_counter, cpu.program_counter + 1)
    |> Map.put(:cycle_count, cpu.cycle_count + 2)
  end

  @doc """
  decrement the given memory location by 1
  """
  def decrement_memory(cpu, addressing_mode) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)
    wrapped_val = Integer.mod(byte - 1, 256)
    memory = Memory.write_byte(cpu.memory, byte_address.address, wrapped_val)

    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        :indexed_indirect -> {2, 6}
      end

    cpu
    |> set_flag_with_test(:negative, wrapped_val)
    |> set_flag_with_test(:zero, wrapped_val)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
    |> Map.put(:memory, memory)
  end

  @doc """
  illegal opcode that implements DEC + CMP
  """
  def dcp(cpu, addressing_mode) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)
    wrapped_val = Integer.mod(byte - 1, 256)
    memory = Memory.write_byte(cpu.memory, byte_address.address, wrapped_val)

    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        :absolute_y -> {3, 7}
        :indexed_indirect -> {2, 8}
        :indirect_indexed -> {2, 8}
      end

    cpu = if cpu.registers.a >= wrapped_val, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)
    cpu = if cpu.registers.a == wrapped_val, do: set_flag(cpu, :zero), else: unset_flag(cpu, :zero)

    cpu
    |> set_flag_with_test(:negative, cpu.registers.a - wrapped_val)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
    |> Map.put(:memory, memory)
  end

  @doc """
  increment the given memory location by 1
  """
  def increment_memory(cpu, addressing_mode) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)
    wrapped_val = rem(byte + 1, 256)
    memory = Memory.write_byte(cpu.memory, byte_address.address, wrapped_val)

    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        _ -> {0, 0}
      end

    cpu
    |> set_flag_with_test(:negative, wrapped_val)
    |> set_flag_with_test(:zero, wrapped_val)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
    |> Map.put(:memory, memory)
  end

  @doc """
  illegal opcode that implements INC + SBC
  """
  def isc(cpu, addressing_mode) do
    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 5}
        :zero_page_x -> {2, 6}
        :absolute -> {3, 6}
        :absolute_x -> {3, 7}
        :absolute_y -> {3, 7}
        :indexed_indirect -> {2, 8}
        :indirect_indexed -> {2, 8}
      end

    orig_pc = cpu.program_counter
    orig_cycle = cpu.cycle_count
    pc = orig_pc + pc
    cycle = orig_cycle + cycle

    cpu
    |> increment_memory(addressing_mode)
    |> Map.put(:program_counter, orig_pc)
    |> Map.put(:cycle_count, orig_cycle)
    |> sbc(addressing_mode)
    |> Map.put(:program_counter, pc)
    |> Map.put(:cycle_count, cycle)
  end

  @doc """
  compare register with a byte from memory and sets flags
  """
  def compare(cpu, addressing_mode, reg) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)

    {pc, cycle} =
      case addressing_mode do
        :immediate -> {2, 2}
        :zero_page -> {2, 3}
        :zero_page_x -> {2, 4}
        :absolute -> {3, 4}
        :absolute_x -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :absolute_y -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :indexed_indirect -> {2, 6}
        :indirect_indexed -> if byte_address.page_crossed, do: {2, 6}, else: {2, 5}
      end

    cpu = if cpu.registers[reg] >= byte, do: set_flag(cpu, :carry), else: unset_flag(cpu, :carry)
    cpu = if cpu.registers[reg] == byte, do: set_flag(cpu, :zero), else: unset_flag(cpu, :zero)

    cpu
    |> set_flag_with_test(:negative, cpu.registers[reg] - byte)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
  end

  @doc """
  load value read at address into the register
  """
  def load_register(cpu, addressing_mode, register) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)

    {pc, cycle} =
      case addressing_mode do
        :immediate -> {2, 2}
        :zero_page -> {2, 3}
        :zero_page_x -> {2, 4}
        :zero_page_y -> {2, 4}
        :absolute -> {3, 4}
        :absolute_x -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :absolute_y -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :indexed_indirect -> {2, 6}
        :indirect_indexed -> if byte_address.page_crossed, do: {2, 6}, else: {2, 5}
      end

    cpu
    |> set_register(register, byte)
    |> set_flag_with_test(:zero, byte)
    |> set_flag_with_test(:negative, byte)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
  end

  @doc """
  illegal opcode that combines LDA + LDX
  """
  def lax(cpu, addressing_mode) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    byte = Memory.read_byte(cpu.memory, byte_address.address)

    {pc, cycle} =
      case addressing_mode do
        :immediate -> {2, 2}
        :zero_page -> {2, 3}
        :zero_page_x -> {2, 4}
        :zero_page_y -> {2, 4}
        :absolute -> {3, 4}
        :absolute_x -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :absolute_y -> if byte_address.page_crossed, do: {3, 5}, else: {3, 4}
        :indexed_indirect -> {2, 6}
        :indirect_indexed -> if byte_address.page_crossed, do: {2, 6}, else: {2, 5}
      end

    cpu
    |> set_register(:a, byte)
    |> set_register(:x, byte)
    |> set_flag_with_test(:zero, byte)
    |> set_flag_with_test(:negative, byte)
    |> Map.put(:program_counter, cpu.program_counter + pc)
    |> Map.put(:cycle_count, cpu.cycle_count + cycle)
  end

  @doc """
  stores the contents of the register into memory
  """
  def store_register(cpu, addressing_mode, register) do
    address = AddressingMode.get_address(addressing_mode, cpu)
    memory = Memory.write_byte(cpu.memory, address.address, cpu.registers[register])

    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 3}
        :zero_page_x -> {2, 4}
        :zero_page_y -> {2, 4}
        :absolute -> {3, 4}
        :absolute_x -> {3, 5}
        :absolute_y -> {3, 5}
        :indexed_indirect -> {2, 6}
        :indirect_indexed -> {2, 6}
      end

    %{cpu | memory: memory, program_counter: cpu.program_counter + pc, cycle_count: cpu.cycle_count + cycle}
  end

  @doc """
  illegal opcode that stores A&X into memory
  """
  def sax(cpu, addressing_mode) do
    address = AddressingMode.get_address(addressing_mode, cpu)
    value = cpu.registers.a &&& cpu.registers.x
    memory = Memory.write_byte(cpu.memory, address.address, value)

    {pc, cycle} =
      case addressing_mode do
        :zero_page -> {2, 3}
        :zero_page_x -> {2, 4}
        :zero_page_y -> {2, 4}
        :absolute -> {3, 4}
        :absolute_x -> {3, 5}
        :absolute_y -> {3, 5}
        :indexed_indirect -> {2, 6}
        :indirect_indexed -> {2, 6}
      end

    %{cpu | memory: memory, program_counter: cpu.program_counter + pc, cycle_count: cpu.cycle_count + cycle}
  end

  @doc """
  transfers the accumulator value to the given register.
  """
  def transfer_accumulator(cpu, source, target) do
    cpu
    |> set_register(target, cpu.registers[source])
    |> set_flag_with_test(:zero, cpu.registers[source])
    |> set_flag_with_test(:negative, cpu.registers[source])
    |> Map.put(:program_counter, cpu.program_counter + 1)
    |> Map.put(:cycle_count, cpu.cycle_count + 2)
  end

  @doc """
  transfers the stack pointer to the x register.
  """
  def transfer_stack_x(cpu) do
    cpu
    |> set_register(:x, cpu.stack_pointer)
    |> set_flag_with_test(:zero, cpu.stack_pointer)
    |> set_flag_with_test(:negative, cpu.stack_pointer)
    |> Map.put(:program_counter, cpu.program_counter + 1)
    |> Map.put(:cycle_count, cpu.cycle_count + 2)
  end

  @doc """
  transfers the to the x register to the stack pointer.
  """
  def transfer_x_stack(cpu) do
    cpu
    |> Map.put(:program_counter, cpu.program_counter + 1)
    |> Map.put(:cycle_count, cpu.cycle_count + 2)
    |> Map.put(:stack_pointer, cpu.registers.x)
  end

  @doc """
  pulls the processor flags from the stack followed by the program counter
  """
  def rti(cpu) do
    {cpu, flag} = pop_byte_off_stack(cpu)

    # make the unused flags match the nestest logs
    flag = flag &&& bnot(@flags[:unused_1])
    flag = bor(flag, @flags[:unused_2])

    {cpu, high} = pop_byte_off_stack(cpu)
    {cpu, low} = pop_byte_off_stack(cpu)
    address = high ||| low <<< 8

    cpu
    |> set_register(:p, flag)
    |> Map.put(:program_counter, address)
    |> Map.put(:cycle_count, cpu.cycle_count + 6)
  end

  @doc """
  push the address (minus one) of the return point to the stack and set the program counter to the memory address
  """
  def jsr(cpu, addressing_mode) do
    byte_address = AddressingMode.get_address(addressing_mode, cpu)
    cpu = push_word_onto_stack(cpu, cpu.program_counter + 2)
    %{cpu | program_counter: byte_address.address, cycle_count: cpu.cycle_count + 6}
  end

  @doc """
  return to the calling routine at the end of a subroutine
  """
  def rts(cpu) do
    {cpu, high} = pop_byte_off_stack(cpu)
    {cpu, low} = pop_byte_off_stack(cpu)

    address = high ||| low <<< 8

    %{cpu | program_counter: address + 1, cycle_count: cpu.cycle_count + 6}
  end

  @doc """
  branch if the given function evaluates to true
  """
  def branch_if(cpu, fun) do
    byte_address = AddressingMode.get_address(:relative, cpu)
    cycles = 2

    {pc, cycles} =
      if fun.(cpu) do
        cycles = if byte_address.page_crossed, do: cycles + 2, else: cycles + 1
        {byte_address.address, cycles}
      else
        {cpu.program_counter + 2, cycles}
      end

    %{cpu | program_counter: pc, cycle_count: cpu.cycle_count + cycles}
  end

  @doc """
  push a copy of the flag register onto the stack
  """
  def php(cpu) do
    # the unused flags need to be set before pushing the value only
    byte =
      cpu.registers.p
      |> bor(@flags[:unused_1])
      |> bor(@flags[:unused_2])

    cpu
    |> push_byte_onto_stack(byte)
    |> Map.put(:program_counter, cpu.program_counter + 1)
    |> Map.put(:cycle_count, cpu.cycle_count + 3)
  end

  @doc """
  push a copy of the accumulator onto the stack
  """
  def pha(cpu) do
    cpu
    |> push_byte_onto_stack(cpu.registers.a)
    |> Map.put(:program_counter, cpu.program_counter + 1)
    |> Map.put(:cycle_count, cpu.cycle_count + 3)
  end

  @doc """
  pop a byte off the stack and store it in the accumlator
  """
  def pla(cpu) do
    {cpu, byte} = pop_byte_off_stack(cpu)

    cpu
    |> set_register(:a, byte)
    |> set_flag_with_test(:zero, byte)
    |> set_flag_with_test(:negative, byte)
    |> Map.put(:program_counter, cpu.program_counter + 1)
    |> Map.put(:cycle_count, cpu.cycle_count + 4)
  end

  @doc """
  pop a byte off the stack and set flags based on its value
  """
  def plp(cpu) do
    {cpu, byte} = pop_byte_off_stack(cpu)

    # make the unused flags match the nestest logs
    byte = byte &&& bnot(@flags[:unused_1])
    byte = bor(byte, @flags[:unused_2])

    cpu
    |> set_register(:p, byte)
    |> Map.put(:program_counter, cpu.program_counter + 1)
    |> Map.put(:cycle_count, cpu.cycle_count + 4)
  end
end
