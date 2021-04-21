# frozen_string_literal: true

module AggregateRoot
  class SnapshotRepository
    def initialize(event_store, interval = 1)
      @event_store = event_store
      @interval    = interval
    end

    def load(aggregate, stream_name)
      snapshot = event_store.read.stream(stream_name).of_type(aggregate.__snapshot_event__.event_type).last
      if snapshot
        aggregate.apply(snapshot)
        event_store.read.stream(stream_name).from(snapshot.event_id).reduce { |_, ev| aggregate.apply(ev) }
      else
        event_store.read.stream(stream_name).reduce { |_, ev| aggregate.apply(ev) }
      end
      aggregate.version = aggregate.unpublished_events.count - 1
      aggregate
    end

    def store(aggregate, stream_name)
      events = aggregate.unpublished_events.to_a

      if snapshot_time(events, stream_name)
        events << aggregate.__snapshot_event__
      end

      event_store.publish(events,
                          stream_name:      stream_name,
                          expected_version: aggregate.version)
      aggregate.version = aggregate.version + events.count
    end

    private

    attr_reader :event_store, :interval

    def snapshot_time(events, stream_name)
      (event_store.read.stream(stream_name).count + events.size) % interval == 0
    end
  end
end
