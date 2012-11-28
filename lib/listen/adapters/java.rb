require 'java' if RUBY_PLATFORM == "java" 

module Listen
  module Adapters

    # Java adapter that works on the JDK platform version 7 or newer.
    # The adapter has no dependencies in addition to the JDK itself.
    # 
    # The JDK chooses an OS specific listener implementation, or 
    # falls back to polling if none is available.
    #
    # @see http://docs.oracle.com/javase/7/docs/api/java/nio/file/WatchService.html
    # @see http://docs.oracle.com/javase/tutorial/essential/io/examples/WatchDir.java
    #
    class Java < Adapter
      extend DependencyManager

      # Initialize the Adapter. See {Listen::Adapter#initialize} for more info.
      #
      def initialize(directories, options = {}, &callback)
        super
      end

      # Start the adapter.
      #
      # @param [Boolean] blocking whether or not to block the current thread after starting
      #
      def start(blocking = true)
        @mutex.synchronize do
          return if @stop == false
          super
        end

        init_watch_service
        @worker_thread = Thread.new { process_events }
        @poll_thread = Thread.new { poll_changed_dirs } if @report_changes
        @worker_thread.join if blocking
      end

      # Stop the adapter.
      #
      def stop
        @mutex.synchronize do
          return if @stop == true
          super
        end

        @watch_service.close
        @worker_thread.join if @worker_thread
        @poll_thread.join if @poll_thread
      end

      # Checks if the adapter is usable on the current OS.
      #
      # @return [Boolean] whether usable or not
      #
      def self.usable?
        return false unless RUBY_PLATFORM == "java" && class_defined?("java.nio.file.WatchService")
        super
      end

      private

        def self.class_defined?(name)
          java.lang.Class.for_name(name)
          true
        rescue java.lang.ClassNotFoundException
          false
        end

        def init_watch_service
          @watch_service = java.nio.file.FileSystems.get_default.new_watch_service()
          @keys = Hash.new
          @directories.each { |dir| watch_recursively(dir) }
        end

        def watch_recursively(dir)
          watch(dir)
          Dir["#{dir}/**/*"].each do |entry|
            watch(entry) if File.directory?(entry)
          end
        end

        def watch(dir)
          path = java.nio.file.FileSystems.get_default.get_path(dir)
          event_kinds = [
            java.nio.file.StandardWatchEventKinds::ENTRY_CREATE,
            java.nio.file.StandardWatchEventKinds::ENTRY_DELETE,
            java.nio.file.StandardWatchEventKinds::ENTRY_MODIFY
          ].to_java(java.nio.file.WatchEvent::Kind)

          # If the Oracle proprietary sentivity modifier is present, use it to get
          # more frequent polling on systems that don't support event based watching.
          key = if Java.class_defined?("com.sun.nio.file.SensitivityWatchEventModifier")
            path.register(@watch_service, event_kinds, com.sun.nio.file.SensitivityWatchEventModifier::HIGH)
          else
            path.register(@watch_service, event_kinds)
          end

          @keys[key] = path
        end

        def process_events
          loop do
            key = @watch_service.take
            next if @paused

            dir = @keys[key]
            next unless dir

            @mutex.synchronize do
              @changed_dirs << dir.to_s
            end

            # If new subdirectories have been added we need to watch them too
            key.poll_events.each do |evt|
              next if evt.kind == java.nio.file.StandardWatchEventKinds::OVERFLOW
              entry = dir.resolve(evt.context).toString()
              if File.directory?(entry)
                watch_recursively(entry)
              end
            end

            # Reset the key back to the watch service.
            # If it is rejected, delete it from our hash. It is no longer relevant.
            unless key.reset()
              @keys.delete(key)
            end
          end
        rescue java.nio.file.ClosedWatchServiceException
          # Will be raised once the adapter stops
        end

    end

  end
end
