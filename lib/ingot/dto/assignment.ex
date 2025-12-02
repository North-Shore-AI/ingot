defmodule Ingot.DTO.Assignment do
  @moduledoc """
  Labeling task with context.

  An assignment represents a single labeling task given to a user,
  including the sample to label, schema definition, and any existing
  labels for review/adjudication scenarios.
  """

  alias Ingot.DTO.{Sample, Label}

  @type t :: %__MODULE__{
          id: String.t(),
          queue_id: String.t(),
          sample: Sample.t(),
          schema: map(),
          existing_labels: [Label.t()],
          assigned_at: DateTime.t(),
          metadata: map()
        }

  defstruct [:id, :queue_id, :sample, :schema, :existing_labels, :assigned_at, :metadata]
end
