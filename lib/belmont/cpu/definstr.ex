defmodule Belmont.CPU.Definstr do
  @moduledoc """
  Macro for defining CPU instructions. Not sure how I feel about this yet...
  """

  @doc """
  Defines `log(cpu, {opcode})` and `execute(cpu, {opcode})` functions for an instruction.

  The call expression is expected to in the form of: `mnemonic(cpu, opcode, operand_size)`.
  The do block is executed as part of the generated execute function.

  Example:

    definstr x86(cpu, "STX", :byte), do: CPU.store_register(cpu, :zero_page, :x)
  """
  defmacro definstr(call, do: expr) do
    # extract the parts from call we need to generate the log and execute functions
    {opcode_str, _meta, [_cpu, mnemonic, operand_size]} = call

    opcode =
      opcode_str
      |> Atom.to_string()
      |> String.trim_leading("x")
      |> String.to_integer(16)

    # define log/2 and execute/2 functions to be used in Belmont.CPU
    quote do
      def log(cpu, unquote(opcode)),
        do: Belmont.CPU.log_state(cpu, unquote(opcode), unquote(mnemonic), unquote(operand_size))

      def execute(var!(cpu), unquote(opcode)) do
        unquote(expr)
      end
    end
  end
end
