# Runs once via gitlab-rails runner: lock the instance down for private use.
s = ApplicationSetting.current
{
  signup_enabled: false,
  require_admin_approval_after_user_signup: true,
  usage_ping_enabled: false,
  version_check_enabled: false,
  snowplow_enabled: false,
  gravatar_enabled: false,
  help_page_hide_commercial_content: true,
  default_project_visibility: Gitlab::VisibilityLevel::PRIVATE,
  default_group_visibility: Gitlab::VisibilityLevel::PRIVATE,
  restricted_visibility_levels: [Gitlab::VisibilityLevel::PUBLIC],
  auto_devops_enabled: false,
  default_branch_name: 'main',
  default_branch_protection: 2
}.each do |k, v|
  begin
    s.update!(k => v)
    puts "ok   #{k}"
  rescue => e
    puts "skip #{k} (#{e.class})"
  end
end
