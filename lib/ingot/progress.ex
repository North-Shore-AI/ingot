defmodule Ingot.Progress do
  @moduledoc """
  Manages broadcasting of progress updates via Phoenix PubSub.

  This module provides functions to broadcast labeling events to all
  connected LiveView processes for real-time progress updates.
  """

  @labels_topic "progress:labels"
  @users_topic "progress:users"
  @queue_topic "progress:queue"

  @doc """
  Broadcast that a label was completed.

  ## Examples

      iex> Progress.broadcast_label_completed("session-123")
      :ok
  """
  def broadcast_label_completed(session_id) do
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      @labels_topic,
      {:label_completed, session_id, DateTime.utc_now()}
    )
  end

  @doc """
  Broadcast that a user joined the labeling interface.

  ## Examples

      iex> Progress.broadcast_user_joined("user-123")
      :ok
  """
  def broadcast_user_joined(user_id) do
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      @users_topic,
      {:user_joined, user_id, DateTime.utc_now()}
    )
  end

  @doc """
  Broadcast that a user left the labeling interface.

  ## Examples

      iex> Progress.broadcast_user_left("user-123")
      :ok
  """
  def broadcast_user_left(user_id) do
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      @users_topic,
      {:user_left, user_id, DateTime.utc_now()}
    )
  end

  @doc """
  Broadcast queue statistics update.

  ## Examples

      iex> Progress.broadcast_queue_update(%{remaining: 453})
      :ok
  """
  def broadcast_queue_update(stats) do
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      @queue_topic,
      {:queue_updated, stats, DateTime.utc_now()}
    )
  end

  @doc """
  Subscribe to label completion events.
  """
  def subscribe_labels do
    Phoenix.PubSub.subscribe(Ingot.PubSub, @labels_topic)
  end

  @doc """
  Subscribe to user join/leave events.
  """
  def subscribe_users do
    Phoenix.PubSub.subscribe(Ingot.PubSub, @users_topic)
  end

  @doc """
  Subscribe to queue updates.
  """
  def subscribe_queue do
    Phoenix.PubSub.subscribe(Ingot.PubSub, @queue_topic)
  end

  @doc """
  Subscribe to all progress events.
  """
  def subscribe_all do
    subscribe_labels()
    subscribe_users()
    subscribe_queue()
  end
end
