# if Rails.env.development?
#   Rails.configuration.after_initialize do
#     Bullet.enable        = true
#     Bullet.alert         = false
#     Bullet.bullet_logger = true
#     Bullet.console       = true
#     Bullet.rails_logger  = true
#     Bullet.add_footer    = true
#   end
# elsif Rails.env.test?
#   Rails.configuration.after_initialize do
#     Bullet.enable        = true
#     Bullet.bullet_logger = true
#     Bullet.raise         = true # raise an error if n+1 query occurs
#   end
# end
