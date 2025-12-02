defmodule Ingot.DTO.QueueStats do
  @moduledoc """
  Queue-level statistics and progress metrics.

  Used for dashboards and progress tracking, showing overall labeling
  progress, agreement metrics, and active participant counts.
  """

  @type t :: %__MODULE__{
          total_samples: integer(),
          labeled: integer(),
          remaining: integer(),
          agreement_scores: map(),
          active_labelers: integer()
        }

  defstruct [:total_samples, :labeled, :remaining, :agreement_scores, :active_labelers]
end
