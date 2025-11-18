# frozen_string_literal: true

require_relative "base_tool"

module HeadlessBrowserTool
  module Tools
    class ResizeWindowTool < BaseTool
      tool_name "resize_window"
      description "Resize the browser window"

      arguments do
        required(:width).filled(:integer).description("Window width in pixels")
        required(:height).filled(:integer).description("Window height in pixels")
      end

      def execute(width:, height:)
        # Get window size before resizing
        size_before = browser.get_window_size

        browser.resize_window(width, height)

        # Get actual window size after resizing
        size_after = browser.get_window_size

        {
          requested_size: {
            width: width,
            height: height
          },
          size_before: {
            width: size_before[0],
            height: size_before[1]
          },
          size_after: {
            width: size_after[0],
            height: size_after[1]
          },
          status: "resized"
        }
      end
    end
  end
end
