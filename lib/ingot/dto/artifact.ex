defmodule Ingot.DTO.Artifact do
  @moduledoc """
  File/blob reference with signed URL.

  Artifacts are media files (images, audio, video, etc.) associated
  with samples. URLs are typically signed and time-limited.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          sample_id: String.t(),
          artifact_type: atom(),
          url: String.t(),
          filename: String.t(),
          size_bytes: integer(),
          content_type: String.t()
        }

  defstruct [:id, :sample_id, :artifact_type, :url, :filename, :size_bytes, :content_type]
end
