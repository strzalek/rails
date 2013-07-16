
module ActionView
  # This is a class to fix I18n global state. Whenever you provide I18n.locale during a request,
  # it will trigger the lookup_context and consequently expire the cache.
  class I18nProxy < ::I18n::Config #:nodoc:
    attr_reader :original_config, :lookup_context

    def initialize(original_config, lookup_context)
      original_config = original_config.original_config if original_config.respond_to?(:original_config)
      @original_config, @lookup_context = original_config, lookup_context
    end

    def locale
      @original_config.locale
    end

    def locale=(value)
      @lookup_context.locale = value
    end
  end

  module Rendering
    extend ActiveSupport::Concern
    include ActionView::ViewPaths

    # Overwrite process to setup I18n proxy.
    def process(*) #:nodoc:
      old_config, I18n.config = I18n.config, I18nProxy.new(I18n.config, lookup_context)
      super
    ensure
      I18n.config = old_config
    end

    module ClassMethods
      def view_context_class
        @view_context_class ||= begin
          routes = respond_to?(:_routes) && _routes
          helpers = respond_to?(:_helpers) && _helpers

          Class.new(ActionView::Base) do
            if routes
              include routes.url_helpers
              include routes.mounted_helpers
            end

            if helpers
              include helpers
            end
          end
        end
      end
    end

    attr_internal_writer :view_context_class

    def view_context_class
      @_view_context_class ||= self.class.view_context_class
    end

    # An instance of a view class. The default view class is ActionView::Base
    #
    # The view class must have the following methods:
    # View.new[lookup_context, assigns, controller]
    #   Create a new ActionView instance for a controller
    # View#render[options]
    #   Returns String with the rendered template
    #
    # Override this method in a module to change the default behavior.
    def view_context
      view_context_class.new(view_renderer, view_assigns, self)
    end

    # Returns an object that is able to render templates.
    def view_renderer
      @_view_renderer ||= ActionView::Renderer.new(lookup_context)
    end

    # Normalize arguments, options and then delegates render_to_body and
    # sticks the result in self.response_body.
    def render(*args, &block)
      super
      options = _normalize_render(*args, &block)
      self.response_body = render_to_body(options)
    end

    def render_to_string(*args, &block)
      options = _normalize_render(*args, &block)
      render_to_body(options)
    end

    # Raw rendering of a template.
    def render_to_body(options = {})
      _process_options(options)
      _render_template(options)
    end

    # Find and renders a template based on the options given.
    # :api: private
    def _render_template(options) #:nodoc:
      lookup_context.rendered_format = nil if options[:formats]
      view_renderer.render(view_context, options)
    end

    def default_protected_instance_vars
      super + [:@_view_context_class, :@_view_renderer, :@_lookup_context]
    end

    private

      # Normalize args and options.
      # :api: private
      def _normalize_render(*args, &block)
        options = _normalize_args(*args, &block)
        _normalize_options(options)
        options
      end

      # Normalize args by converting render "foo" to render :action => "foo" and
      # render "foo/bar" to render :file => "foo/bar".
      def _normalize_args(action=nil, options={})
        options = super(action, options)
        case action
        when NilClass
        when Hash
          options = action
        when String, Symbol
          action = action.to_s
          key = action.include?(?/) ? :file : :action
          options[key] = action
        else
          options[:partial] = action
        end

        options
      end

      # Normalize options.
      def _normalize_options(options)
        options = super(options)
        if options[:partial] == true
          options[:partial] = action_name
        end

        if (options.keys & [:partial, :file, :template]).empty?
          options[:prefixes] ||= _prefixes
        end

        options[:template] ||= (options[:action] || action_name).to_s
        options
      end
  end
end