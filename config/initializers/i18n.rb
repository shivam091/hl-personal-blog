# -*- encoding: utf-8 -*-
# -*- frozen_string_literal: true -*-
# -*- warn_indent: true -*-

# Nested folders and .yaml files too, which Rails' default path leaves out.
HLPersonalBlog::Application.config.i18n.load_path += Dir[Rails.root.join("config", "locales", "**", "*.{rb,yml,yaml}")]

HLPersonalBlog::Application.config.i18n.available_locales = [:en]

I18n.default_locale = :en
