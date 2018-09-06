defmodule EvercamMedia.UserMailer do
  use Bamboo.Phoenix, view: EvercamMediaWeb.EmailView
  alias EvercamMedia.Mailer
  alias EvercamMedia.Snapshot.Storage
  alias EvercamMedia.Snapshot.CamClient
  import SnapmailLogs, only: [save_snapmail: 4]
  import Bamboo.Email

  @config Application.get_env(:evercam_media, :mailgun)
  @from Application.get_env(:evercam_media, EvercamMediaWeb.Endpoint)[:email]
  @year Calendar.DateTime.now_utc |> Calendar.Strftime.strftime!("%Y")

  def cr_settings_changed(current_user, camera, cloud_recording, old_cloud_recording, user_request_ip) do
    new_email()
    |> to("junaid@evercam.io")
    |> from(@from)
    |> subject("Cloud Recording has been updated for \"#{camera.name}\"")
    |> bcc(["junaid@evercam.io"])
    |> assign(:camera, camera)
    |> assign(:current_user, current_user)
    |> assign(:cloud_recording, cloud_recording)
    |> assign(:old_cloud_recording, old_cloud_recording)
    |> assign(:user_request_ip, user_request_ip)
    |> assign(:year, @year)
    |> put_text_layout({EvercamMediaWeb.EmailView, "cr_settings_changed.txt"})
    |> put_html_layout({EvercamMediaWeb.EmailView, "cr_settings_changed.html"})
    |> render(:text_and_html_email)
    |> Mailer.deliver_now()
  end

  def confirm(user, code) do
    new_email()
    |> to(user.email)
    |> from(@from)
    |> subject("Evercam Confirmation")
    |> assign(:user, user)
    |> assign(:code, code)
    |> assign(:year, @year)
    |> put_text_layout({EvercamMediaWeb.EmailView, "confirm.txt"})
    |> put_html_layout({EvercamMediaWeb.EmailView, "confirm.html"})
    |> render(:text_and_html_email)
    |> Mailer.deliver_now()
  end

  def camera_status(status, _user, camera) do
    timezone = camera |> Camera.get_timezone
    current_time = Calendar.DateTime.now_utc |> Calendar.DateTime.shift_zone!(timezone) |> Calendar.Strftime.strftime!("%A, %d %b %Y %H:%M")
    thumbnail = get_thumbnail(camera, status)
    camera.alert_emails
    |> String.split(",", trim: true)
    |> Enum.each(fn(email) ->
      new_email()
      |> to(email)
      |> from(@from)
      |> subject("\"#{camera.name}\" camera is now #{status}")
      |> assign(:user, email)
      |> assign(:camera, camera)
      |> assign(:thumbnail_available, !!thumbnail)
      |> assign(:current_time, current_time)
      |> assign(:year, @year)
      |> add_attachment(thumbnail)
      |> put_text_layout({EvercamMediaWeb.EmailView, "#{status}.txt"})
      |> put_html_layout({EvercamMediaWeb.EmailView, "#{status}.html"})
      |> render(:text_and_html_email)
      |> Mailer.deliver_now()
    end)
  end

  def camera_offline_reminder(_user, camera, subject) do
    timezone = camera |> Camera.get_timezone
    current_time =
      camera.last_online_at
      |> Ecto.DateTime.to_erl
      |> Calendar.DateTime.from_erl!("UTC")
      |> Calendar.DateTime.shift_zone!(timezone)
      |> Calendar.Strftime.strftime!("%A, %d %b %Y %H:%M")
    thumbnail = get_thumbnail(camera)
    camera.alert_emails
    |> String.split(",", trim: true)
    |> Enum.each(fn(email) ->
      new_email()
      |> to(email)
      |> from(@from)
      |> subject("#{subject} reminder: \"#{camera.name}\" camera has gone offline")
      |> assign(:user, email)
      |> assign(:camera, camera)
      |> assign(:thumbnail_available, !!thumbnail)
      |> assign(:current_time, current_time)
      |> assign(:year, @year)
      |> add_attachment(thumbnail)
      |> put_text_layout({EvercamMediaWeb.EmailView, "offline.txt"})
      |> put_html_layout({EvercamMediaWeb.EmailView, "offline.html"})
      |> render(:text_and_html_email)
      |> Mailer.deliver_now()
    end)
  end

  def camera_shared_notification(user, camera, sharee_email, message) do
    thumbnail = get_thumbnail(camera)
    new_email()
    |> to(sharee_email)
    |> from(@from)
    |> bcc([user.email])
    |> put_header("Reply-To", user.email)
    |> subject("#{User.get_fullname(user)} has shared the camera #{camera.name} with you.")
    |> assign(:user, user)
    |> assign(:camera, camera)
    |> assign(:thumbnail_available, !!thumbnail)
    |> assign(:message, message)
    |> assign(:year, @year)
    |> add_attachment(thumbnail)
    |> put_text_layout({EvercamMediaWeb.EmailView, "camera_shared_notification.txt"})
    |> put_html_layout({EvercamMediaWeb.EmailView, "camera_shared_notification.html"})
    |> render(:text_and_html_email)
    |> Mailer.deliver_now()
  end

  def camera_share_request_notification(user, camera, email, message, key) do
    thumbnail = get_thumbnail(camera)
    new_email()
    |> to(email)
    |> from(@from)
    |> bcc([user.email, "marco@evercam.io", "vinnie@evercam.io", "erin@evercam.io"])
    |> put_header("Reply-To", user.email)
    |> subject("#{User.get_fullname(user)} has shared the camera #{camera.name} with you.")
    |> assign(:user, user)
    |> assign(:sharee, email)
    |> assign(:key, key)
    |> assign(:camera, camera)
    |> assign(:thumbnail_available, !!thumbnail)
    |> assign(:message, message)
    |> assign(:year, @year)
    |> add_attachment(thumbnail)
    |> put_text_layout({EvercamMediaWeb.EmailView, "sign_up_to_share_email.txt"})
    |> put_html_layout({EvercamMediaWeb.EmailView, "sign_up_to_share_email.html"})
    |> render(:text_and_html_email)
    |> Mailer.deliver_now()
  end

  def accepted_share_request_notification(user, camera, email) do
    thumbnail = get_thumbnail(camera)
    Mailgun.Client.send_email @config,
      to: user.email,
      subject: "#{email} has accepted your request to view your camera",
      from: @from,
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "accepted_share_request.html", user: user, camera: camera, sharee: email, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "accepted_share_request.txt", user: user, camera: camera, sharee: email)
  end

  def revoked_share_request_notification(user, camera, email) do
    thumbnail = get_thumbnail(camera)
    Mailgun.Client.send_email @config,
      to: user.email,
      subject: "#{email} did not accept your request to view your camera",
      from: @from,
      bcc: "marco@evercam.io,vinnie@evercam.io,erin@evercam.io",
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "revoke_share_request.html", user: user, camera: camera, sharee: email, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "revoke_share_request.txt", user: user, camera: camera, sharee: email)
  end

  def camera_create_notification(user, camera) do
    thumbnail = get_thumbnail(camera)
    Mailgun.Client.send_email @config,
      to: user.email,
      subject: "A new camera has been added to your account",
      from: @from,
      bcc: "marco@evercam.io,vinnie@evercam.io,erin@evercam.io",
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "camera_create_notification.html", user: user, camera: camera, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "camera_create_notification.txt", user: user, camera: camera)
  end

  def password_reset_request(user) do
    Mailgun.Client.send_email @config,
      to: user.email,
      subject: "Password reset requested for Evercam",
      from: @from,
      html: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "password_reset_request.html", user: user, year: @year),
      text: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "password_reset_request.txt", user: user)
  end

  def archive_completed(archive, email) do
    thumbnail = get_thumbnail(archive.camera)
    Mailgun.Client.send_email @config,
      to: email,
      subject: "Archive #{archive.title} is ready.",
      from: @from,
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "archive_create_completed.html", archive: archive, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "archive_create_completed.txt", archive: archive, thumbnail_available: !!thumbnail, year: @year)
  end

  def archive_failed(archive, email) do
    thumbnail = get_thumbnail(archive.camera)
    Mailgun.Client.send_email @config,
      to: email,
      subject: "Archive #{archive.title} is failed.",
      from: @from,
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "archive_create_failed.html", archive: archive, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "archive_create_failed.txt", archive: archive, thumbnail_available: !!thumbnail, year: @year)
  end

  def snapmail(id, notify_time, recipients, camera_images, timestamp) do
    attachments = get_multi_attachments(camera_images)
    recipients
    |> String.split(",", trim: true)
    |> Enum.each(fn(recipient) ->
      Mailgun.Client.send_email @config,
        to: recipient,
        subject: "Your Scheduled SnapMail @ #{notify_time}",
        from: @from,
        attachments: attachments,
        html: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "snapmail.html", id: id, recipient: recipient, notify_time: notify_time, camera_images: camera_images, year: @year),
        text: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "snapmail.txt", id: id, recipient: recipient, notify_time: notify_time, camera_images: camera_images, year: @year)
    end)
    save_snapmail(recipients, "Your Scheduled SnapMail @ #{notify_time}",
      Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "snapmail.html", id: id, recipient: "history_user", notify_time: notify_time, camera_images: camera_images, year: @year), "#{timestamp}")
  end

  def snapshot_extraction_started(snapshot_extractor) do
    from_d = get_formatted_date(snapshot_extractor.from_date)
    to_d = get_formatted_date(snapshot_extractor.to_date)
    Mailgun.Client.send_email @config,
      to: snapshot_extractor.requestor,
      subject: "Snapshot Extraction (Local) started",
      from: @from,
      html: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "snapshot_extractor_alert.html", snapshot_extractor: snapshot_extractor, from_d: from_d, to_d: to_d, interval: parse_interval(Integer.floor_div(snapshot_extractor.interval, 60)), year: @year),
      text: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "snapshot_extractor_alert.txt", snapshot_extractor: snapshot_extractor, from_d: from_d, to_d: to_d, interval: parse_interval(Integer.floor_div(snapshot_extractor.interval, 60)), year: @year)
  end

  def snapshot_extraction_completed(snapshot_extractor, snap_count) do
    url = get_dropbox_url(snapshot_extractor)
    Mailgun.Client.send_email @config,
      to: snapshot_extractor.requestor,
      subject: "Snapshot Extraction (Local) Completed",
      from: @from,
      html: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "snapshot_extractor_complete.html", camera: snapshot_extractor.camera.name, count: snap_count, dropbox_url: url, year: @year),
      text: Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "snapshot_extractor_complete.txt", camera: snapshot_extractor.camera.name, count: snap_count, dropbox_url: url, year: @year)
  end

  defp add_attachment(email, nil), do: email
  defp add_attachment(email, thumbnail) do
    email |> put_attachment(%Bamboo.Attachment{data: thumbnail, filename: "snapshot.jpg"})
  end

  defp get_thumbnail(camera, status \\ "")
  defp get_thumbnail(camera, "online") do
    case camera |> construct_args |> fetch_snapshot do
      {:ok, data} -> data
      {:error, _error} -> try_get_thumbnail(camera, 3)
    end
  end
  defp get_thumbnail(camera, _status) do
    try_get_thumbnail(camera, 1)
  end

  defp try_get_thumbnail(camera, 3) do
    case Storage.thumbnail_load(camera.exid) do
      {:ok, _, ""} -> nil
      {:ok, _, image} -> image
      _ -> nil
    end
  end
  defp try_get_thumbnail(camera, attempt) do
    case Storage.thumbnail_load(camera.exid) do
      {:ok, _, ""} -> try_get_thumbnail(camera, attempt + 1)
      {:ok, _, image} -> image
      _ -> nil
    end
  end

  defp get_attachments(thumbnail) do
    if thumbnail, do: %Bamboo.Attachment{data: thumbnail, filename: "snapshot.jpg"}, else: nil
  end

  defp get_multi_attachments(camera_images) do
    camera_images
    |> Enum.map(fn(camera_image) ->
      if !!camera_image.data do
        %{content: camera_image.data, filename: "#{camera_image.exid}.jpg"}
      end
    end)
    |> Enum.reject(fn(content) -> content == nil end)
  end

  defp fetch_snapshot(args, attempt \\ 1) do
    response = CamClient.fetch_snapshot(args)

    case {response, attempt} do
      {{:error, _error}, attempt} when attempt <= 3 ->
        fetch_snapshot(args, attempt + 1)
      _ -> response
    end
  end

  defp construct_args(camera) do
    %{
      camera_exid: camera.exid,
      is_online: camera.is_online,
      url: Camera.snapshot_url(camera),
      username: Camera.username(camera),
      password: Camera.password(camera),
      vendor_exid: Camera.get_vendor_attr(camera, :exid)
    }
  end

  defp parse_interval(60), do: "1 Frame Every hour"
  defp parse_interval(interval) when interval < 60, do: "1 Frame Every #{interval} min"
  defp parse_interval(interval) when interval > 60, do: "1 Frame Every #{Integer.floor_div(interval, 60)} hours"

  defp get_formatted_date(datetime) do
    datetime
    |> Ecto.DateTime.to_erl
    |> Calendar.Strftime.strftime!("%A, %d %b %Y %H:%M")
  end

  defp get_dropbox_url(snapshot_extractor) do
    "https://www.dropbox.com/home/#{construction_request(snapshot_extractor.requestor)}/#{snapshot_extractor.camera.exid}/#{snapshot_extractor.id}"
  end

  defp construction_request("marklensmen@gmail.com"), do: "Construction"
  defp construction_request(_), do: "Construction2"
end
