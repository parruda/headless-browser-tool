# frozen_string_literal: true

require "capybara"
require "capybara/dsl"
require "selenium-webdriver"

module HeadlessBrowserTool
  class Browser
    include Capybara::DSL

    attr_reader :session
    attr_accessor :previous_state

    def initialize(headless: true)
      configure_capybara(headless)
      @session = Capybara.current_session
      @previous_state = {}
    end

    def active?
      !@session.driver.browser.nil?
    rescue StandardError
      false
    end

    # Navigation tools
    def visit(url)
      @session.visit(url)
      { message: "Navigated to #{url}" }
    end

    def refresh
      @session.refresh
      { message: "Page refreshed" }
    end

    def go_back
      @session.go_back
      { message: "Navigated back" }
    end

    def go_forward
      @session.go_forward
      { message: "Navigated forward" }
    end

    # Interaction tools
    def click(selector)
      element = @session.find(selector)
      element.click
      { message: "Clicked element: #{selector}" }
    end

    def right_click(selector)
      element = @session.find(selector)
      element.right_click
      { message: "Right-clicked element: #{selector}" }
    end

    def double_click(selector)
      element = @session.find(selector)
      element.double_click
      { message: "Double-clicked element: #{selector}" }
    end

    def hover(selector)
      element = @session.find(selector)
      element.hover
      { message: "Hovered over element: #{selector}" }
    end

    def drag(source_selector, target_selector)
      source = @session.find(source_selector)
      target = @session.find(target_selector)
      source.drag_to(target)
      { message: "Dragged from #{source_selector} to #{target_selector}" }
    end

    # Element tools
    def find_element(selector)
      element = @session.find(selector)
      {
        tag_name: element.tag_name,
        text: element.text,
        visible: element.visible?,
        location: { x: element.native.location.x, y: element.native.location.y }
      }
    end

    def find_all(selector)
      elements = @session.all(selector)
      elements.map do |element|
        {
          tag_name: element.tag_name,
          text: element.text,
          visible: element.visible?,
          attributes: extract_attributes(element),
          value: element.value
        }
      end
    end

    def get_text(selector)
      element = @session.find(selector)
      element.text
    end

    def get_attribute(selector, attribute_name)
      element = @session.find(selector)
      element[attribute_name]
    end

    def get_value(selector)
      element = @session.find(selector)
      element.value
    end

    def is_visible?(selector)
      element = @session.find(selector)
      element.visible?
    rescue Capybara::ElementNotFound
      false
    end

    def has_element?(selector, wait_seconds = nil)
      if wait_seconds
        @session.has_selector?(selector, wait: wait_seconds)
      else
        @session.has_selector?(selector)
      end
    end

    def has_text?(text, wait_seconds = nil)
      if wait_seconds
        @session.has_text?(text, wait: wait_seconds)
      else
        @session.has_text?(text)
      end
    end

    # Form tools
    def fill_in(field, value)
      @session.fill_in(field, with: value)
      { message: "Filled '#{field}' with '#{value}'" }
    end

    def select(value, dropdown_selector)
      @session.select(value, from: dropdown_selector)
      { message: "Selected '#{value}' from '#{dropdown_selector}'" }
    end

    def check(checkbox_selector)
      @session.check(checkbox_selector)
      { message: "Checked '#{checkbox_selector}'" }
    end

    def uncheck(checkbox_selector)
      @session.uncheck(checkbox_selector)
      { message: "Unchecked '#{checkbox_selector}'" }
    end

    def choose(radio_button_selector)
      @session.choose(radio_button_selector)
      { message: "Chose '#{radio_button_selector}'" }
    end

    def attach_file(file_field_selector, file_path)
      @session.attach_file(file_field_selector, file_path)
      { message: "Attached '#{file_path}' to '#{file_field_selector}'" }
    end

    def click_button(button_text_or_selector)
      @session.click_button(button_text_or_selector)
      { message: "Clicked button: #{button_text_or_selector}" }
    end

    def click_link(link_text_or_selector)
      @session.click_link(link_text_or_selector)
      { message: "Clicked link: #{link_text_or_selector}" }
    end

    # Info tools
    def get_current_url
      @session.current_url
    end

    def get_current_path
      @session.current_path
    end

    def get_page_title
      @session.title
    end

    def get_page_source
      @session.html
    end

    # JavaScript tools
    def execute_script(javascript_code)
      @session.execute_script(javascript_code)
      { message: "Executed JavaScript" }
    end

    def evaluate_script(javascript_code)
      @session.evaluate_script(javascript_code)
    end

    # Utility tools
    def save_screenshot(file_path)
      @session.save_screenshot(file_path)
      { message: "Screenshot saved to #{file_path}" }
    end

    def save_page(file_path)
      @session.save_page(file_path)
      { message: "Page saved to #{file_path}" }
    end

    # Window tools
    def switch_to_window(window_handle)
      @session.switch_to_window(window_handle)
      current_window = @session.current_window

      {
        status: "success",
        window_handle: current_window.handle,
        current_url: @session.current_url,
        title: @session.title,
        position: get_window_position,
        size: get_window_size,
        is_current: true,
        total_windows: @session.windows.length
      }
    end

    def open_new_window
      initial_windows_count = @session.windows.length
      window = @session.open_new_window

      # Switch to the new window to get its info
      @session.switch_to_window(window)

      {
        status: "success",
        window_handle: window.handle,
        current_url: @session.current_url,
        title: @session.title,
        position: get_window_position,
        size: get_window_size,
        is_current: true,
        total_windows: @session.windows.length,
        previous_windows_count: initial_windows_count
      }
    end

    def close_window(window_handle)
      initial_windows_count = @session.windows.length
      current_handle = @session.current_window.handle
      window = @session.windows.find { |w| w.handle == window_handle }

      if window.nil?
        return {
          status: "error",
          error: "Window not found",
          window_handle: window_handle
        }
      end

      # If closing the current window, switch to another first
      if window_handle == current_handle && @session.windows.length > 1
        other_window = @session.windows.find { |w| w.handle != window_handle }
        @session.switch_to_window(other_window) if other_window
      end

      window.close

      {
        status: "success",
        closed_window_handle: window_handle,
        remaining_windows: @session.windows.length,
        initial_windows_count: initial_windows_count,
        current_window_handle: @session.windows.any? ? @session.current_window.handle : nil
      }
    end

    def get_window_handles
      @session.windows.map(&:handle)
    end

    def maximize_window
      current_window = @session.current_window
      size_before = get_window_size

      current_window.maximize

      size_after = get_window_size

      {
        status: "success",
        window_handle: current_window.handle,
        size_before: size_before,
        size_after: size_after,
        current_url: @session.current_url,
        title: @session.title
      }
    end

    def resize_window(width, height)
      current_window = @session.current_window
      size_before = get_window_size

      current_window.resize_to(width, height)

      size_after = get_window_size

      {
        status: "success",
        window_handle: current_window.handle,
        size_before: size_before,
        size_after: size_after,
        requested_size: { width: width, height: height },
        actual_size: size_after,
        current_url: @session.current_url,
        title: @session.title
      }
    end

    def get_window_size
      size = @session.current_window.size
      { width: size[0], height: size[1] }
    rescue StandardError
      { width: nil, height: nil }
    end

    private

    def extract_attributes(element)
      # Get common attributes that are often useful
      attrs = {}
      %w[id class href src alt title name type value placeholder data-testid role aria-label].each do |attr|
        value = element[attr]
        attrs[attr] = value if value && !value.empty?
      end
      attrs
    end

    def get_window_position
      # Try to get window position, but this might not be supported by all drivers

      browser = @session.driver.browser
      position = browser.manage.window.position
      { x: position.x, y: position.y }
    rescue StandardError
      { x: nil, y: nil }
    end

    def configure_capybara(headless)
      Capybara.register_driver :selenium_chrome do |app|
        options = Selenium::WebDriver::Chrome::Options.new
        options.add_argument("--headless") if headless
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("--disable-gpu") if headless

        Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
      end

      Capybara.default_driver = :selenium_chrome
      Capybara.javascript_driver = :selenium_chrome
      Capybara.default_max_wait_time = 10
    end
  end
end
