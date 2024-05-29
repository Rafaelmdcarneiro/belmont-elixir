defmodule Mix.Tasks.Nestest do
  @moduledoc """
  Task to run an compare the CPU output with a known good log file
  """

  use Mix.Task

  @shortdoc "Run the CPU against the nestest test rom and compare logs"
  def run(_) do
    nestest_logs = load_nestest_logs()

    # read the nestest cart and setup the system
    {:ok, cart} = Belmont.Cartridge.load_rom("nestest/nestest.nes")

    cpu =
      cart
      |> Belmont.Memory.new()
      |> Belmont.CPU.new()
      |> Map.put(:program_counter, 0xC000)

    step(cpu, nestest_logs)
  end

  defp step(cpu, [nestest_log | log_tail]) do
    opcode = Belmont.Memory.read_byte(cpu.memory, cpu.program_counter)
    log = Belmont.CPU.Instructions.log(cpu, opcode)
    IO.puts(log)

    if !log_lines_match?(log, nestest_log) do
      IO.puts("mistmatched log lines: \n#{log} -- Belmont\n#{nestest_log} -- Nestest")
      :timer.sleep(500)
      Process.exit(self(), :normal)
    end

    cpu
    |> Belmont.CPU.step()
    |> step(log_tail)
  end

  defp log_lines_match?(belmont_log, nestest_log) do
    # just make sure the first and last parts of the log lines match
    belmont_beginning = String.slice(belmont_log, 0..19) |> String.trim()
    nestest_beginning = String.slice(nestest_log, 0..19) |> String.trim()

    belmont_end = String.slice(belmont_log, 48..80) |> String.trim()
    nestest_end = String.slice(nestest_log, 48..80) |> String.trim()

    # adjust the nestest log for unsupported opcodes, just to make things easy
    # until we have a PPU
    nestest_beginning = Regex.replace(~r/\*(\w+)/, nestest_beginning, " *\\1")

    belmont_beginning == nestest_beginning && belmont_end == nestest_end
  end

  defp load_nestest_logs() do
    {:ok, contents} = File.read("./nestest/nestest.log")

    contents
    |> String.split("\r\n", trim: true)
  end
end
