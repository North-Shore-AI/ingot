defmodule Ingot.DTO.Sample do
  @moduledoc """
  UI-friendly sample representation.

  This DTO decouples Ingot from Forge's internal sample schema,
  providing a stable interface optimized for rendering.
  """

  alias Ingot.DTO.Artifact

  @type t :: %__MODULE__{
          id: String.t(),
          pipeline_id: String.t(),
          payload: map(),
          artifacts: [Artifact.t()],
          metadata: map(),
          created_at: DateTime.t()
        }

  defstruct [:id, :pipeline_id, :payload, :artifacts, :metadata, :created_at]
end
