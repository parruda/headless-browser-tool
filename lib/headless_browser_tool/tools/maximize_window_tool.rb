# frozen_string_literal: true

require_relative "base_tool"

module HeadlessBrowserTool
  module Tools
    class MaximizeWindowTool < BaseTool
      tool_name "maximize_window"
      description "Maximize the browser window"

      def execute
        # Get window size before maximizing
        size_before = browser.get_window_size

        browser.maximize_window

        # Get window size after maximizing
        size_after = browser.get_window_size

        {
          size_before: {
            width: size_before[0],
            height: size_before[1]
          },
          size_after: {
            width: size_after[0],
            height: size_after[1]
          },
          status: "maximized"
        }
      end
    end
  end
end
