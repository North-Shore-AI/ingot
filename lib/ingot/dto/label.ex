defmodule Ingot.DTO.Label do
  @moduledoc """
  A completed label submission.

  Labels represent human judgments about samples, including ratings,
  classifications, or free-text annotations.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          assignment_id: String.t(),
          sample_id: String.t(),
          labeler_id: String.t(),
          values: map(),
          created_at: DateTime.t()
        }

  defstruct [:id, :assignment_id, :sample_id, :labeler_id, :values, :created_at]
end
