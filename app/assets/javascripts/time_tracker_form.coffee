updateTimeTrackerControlForm = (data) ->
  chronos.Utils.clearFlash()
  $.ajax
    url: chronosRoutes.chronos_time_tracker('current')
    type: 'put'
    data: data
    error: ({responseJSON}) ->
      chronos.Utils.showErrorMessage responseJSON.message

$ ->
  $timeTrackerControl = $('.time-tracker-control')
  $issueTextField = $timeTrackerControl.find('#issue_text')
  $projectSelectField = $timeTrackerControl.find('#time_tracker_project_id')
  $activitySelectField = $timeTrackerControl.find('#time_tracker_activity_id')

  $timeTrackerControl.on 'change', (e) ->
    data = {}
    $target = $(e.target)
    $target = $target.next() if $target.hasClass('js-linked-with-hidden')
    data[$target.attr('name')] = $target.val()
    updateTimeTrackerControlForm data
    chronos.FormValidator.validateField $target

  $issueTextField.on 'change', ->
    $this = $(@)
    $this.next().val('') if $this.val() is ''

  $projectSelectField.on 'change', ->
    $issueTextField.val('').trigger('change') unless $issueTextField.val() is ''
    chronos.Utils.updateActivityField $activitySelectField