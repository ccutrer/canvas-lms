class BrandConfigsController < ApplicationController

  include Api::V1::Progress

  before_filter :require_user
  before_filter :require_manage_account_settings, except: [:destroy]

  def new
    @page_title = join_title(t('Theme Editor'), @domain_root_account.name)
    css_bundle :common, :theme_editor
    js_bundle :theme_editor
    brand_config = active_brand_config || BrandConfig.new
    js_env brandConfig: brand_config.as_json(include_root: false),
           hasUnsavedChanges: session.key?(:brand_config_md5),
           variableSchema: BrandableCSS::BRANDABLE_VARIABLES,
           sharedBrandConfigs: BrandConfig.shared(@domain_root_account).select('md5, name').as_json(include_root: false),
           allowGlobalIncludes: @domain_root_account.allow_global_includes?
    render text: '', layout: 'layouts/bare'
  end

  # Preview/Create New BrandConfig
  # This is what is called when the user hits 'preview changes' in the theme editor.
  #
  # @argument brand_config[variables] see app/stylesheets/brandable_variables.json for an example of
  #   which variables can be set.
  #
  # If you send your request in mimeType: 'multipart/form-data' then you can have it upload images to use.
  # If the css files for this BrandConfig have not been created yet, it will return a `Progress` object
  # indicating the progress of generating the css and pushing it to the CDN
  # @returns {BrandConfig, Progress}
  def create
    variables = process_variables(params[:brand_config][:variables])
    js_overrides = process_file(params[:js_overrides])
    css_overrides = process_file(params[:css_overrides])

    brand_config = BrandConfig.for(
      variables: variables,
      js_overrides: js_overrides,
      css_overrides: css_overrides
    )

    if existing_config(brand_config)
      render json: { brand_config: brand_config.as_json(include_root: false) }
    else
      render json: {
        brand_config: brand_config.as_json(include_root: false),
        progress: progress_json(generate_css(brand_config), @current_user, session)
      }
    end
  end

  def existing_config(config)
    config.default? || !config.new_record?
  end
  private :existing_config

  # Activiate a given brandConfig for the current users's session.
  # this is what is called after the user pushes "Preview"
  # and after the progress of generating and pushing the css files to the CDN.
  # Or when they pick an existing one from the dropdown of starter themes.
  #
  # @argument brand_config_md5 [String]
  #   If set, will activate this specific brand config as the active one in the session.
  #   If the empty string ('') is passed, will use nothing for this session
  #   (so the user will see the canvas default theme).
  def save_to_user_session
    old_md5 = session[:brand_config_md5]
    session[:brand_config_md5] = begin
      if params[:brand_config_md5] == ''
        false
      elsif params[:brand_config_md5]
        BrandConfig.find(params[:brand_config_md5]).md5
      end
    end
    BrandConfig.destroy_if_unused(old_md5) if old_md5 != session[:brand_config_md5]
    redirect_to brand_configs_new_path
  end

  # After someone is satisfied with the preview of how their session brand config looks,
  # they POST to this action to save it to their accout so everyone else sees it.
  def save_to_account
    old_md5 = @domain_root_account.brand_config_md5
    new_md5 = session.delete(:brand_config_md5).presence
    @domain_root_account.brand_config = new_md5 && BrandConfig.find(new_md5)
    @domain_root_account.save!
    BrandConfig.destroy_if_unused(old_md5)
    redirect_to account_path(@domain_root_account), notice: t('Success! All users on this domain will now see this branding.')
  end

  # When you close the theme editor, it will send a DELETE to this action to
  # clear out the session brand_config that you were prevewing.
  def destroy
    if session.delete(:brand_config_md5).presence
      session.delete(:brand_config_md5)
      BrandConfig.destroy_if_unused(session.delete(:brand_config_md5))
    end
    redirect_to account_path(@domain_root_account), notice: t('Theme editor changes have been cancelled.')
  end

  protected

  def require_manage_account_settings
    return false unless authorized_action(@domain_root_account,
                                          @current_user,
                                          :manage_account_settings) && use_new_styles?
  end

  def process_variables(variables)
    variables.each_with_object({}) do |(key, value), memo|
      next unless value.present? && (config = BrandableCSS.variables_map[key])
      value = process_file(value) if config['type'] == 'image'
      memo[key] = value
    end
  end

  def process_file(file)
    if file.is_a?(ActionDispatch::Http::UploadedFile)
      upload_file(file)
    else
      file
    end
  end

  def generate_css(brand_config)
    brand_config.save!
    progress = Progress.new(context: @current_user, tag: :brand_config_save_and_sync_to_s3)
    progress.user = @current_user
    progress.reset!
    progress.process_job(brand_config, :save_and_sync_to_s3!, priority: Delayed::HIGH_PRIORITY)
    progress
  end

  def upload_file(file)
    attachment = Attachment.create(uploaded_data: file, context: @domain_root_account)
    expires_in = 15.years
    attachment.authenticated_s3_url({
      # this is how long the s3 verifier token will work
      expires: expires_in,
      # these are the http cache headers that will be set on the response
      response_expires: expires_in,
      response_cache_control: "Cache-Control:max-age=#{expires_in}, public"
    })
  end

end
