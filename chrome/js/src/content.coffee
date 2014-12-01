(($, window) ->

  log = (args...) ->
    if console?.log and mb?.debug is true
      args.unshift "[#{M.CLS}]"
      console.log.apply console, args
    return

  __msg = chrome.i18n.getMessage

  class M
    debug:   false

    @SCHEDULE_SUFFIX: '/schedule'
    @SETUP_URL_SUFFIX: '/setup'

    @CLS:         'mailfred'
    #@CLS_NAV:     M.CLS + '-nav'
    @CLS_THREAD:   M.CLS + '-thread'
    @CLS_POPUP:    M.CLS + '-popup'
    @CLS_MENU:     M.CLS + '-menu'
    @CLS_PICKER:   M.CLS + '-picker'
    @CLS_LOADER:   M.CLS + '-loader'
    @CLS_AUTH_IMG: M.CLS + '-auth-image'
    @CLS_AUTH_TXT: M.CLS + '-auth-text'

    @ID_PREFIX:    M.CLS + '-id-'

    @TYPE_THREAD:  'thread'
    @TYPE_NAV:     'nav'

    @STORE:
      BOX_SETTING:  'settings'
      DEBUG:        'debug'
      EMAIL:        'email'
      LAST_VERSION: 'lastVersion'

    @GM_SEL:
      ARCHIVE_BUTTON:                 '.T-I.J-J5-Ji.lR.T-I-ax7.T-I-Js-IF.ar7:visible'
      THREAD_BUTTON_BAR:              '.iH > div'
      INSERT_AFTER:                   '.G-Ni.J-J5-Ji:visible:nth-child(3)'
      PREVIEW_PANE_ENABLED:           '.apF .apJ'
      PREVIEW_PANE_THREAD_BUTTON_BAR:  "[gh='mtb'] > div > div"

    # URL
    url: null

    # Current GMail address of the logged in user
    currentGmail: null
    settingEmail: null
    settingProps: {}
    selectedConversationId: null

    currentView: null
    currentVersion: null

    constructor: ->
      window.addEventListener "message", @messageListener, false

      @initSettings()

      # Get the service URL
      chrome.runtime.sendMessage {action: 'url'}, (url) =>
        @url = url
        @checkVersion()
        return

    initSettings: ->
      # Get the settings
      chrome.storage.local.get null, (items) =>
        _.each items, (value, key) =>
          switch key
            when M.STORE.DEBUG
              @debug = value
              log 'MailFred debugging is enabled' if @debug
            when M.STORE.EMAIL
              @settingEmail = value
          return
        return

      # Get the selected options
      chrome.storage.sync.get M.STORE.BOX_SETTING, (items) =>
        @settingProps = items[M.STORE.BOX_SETTING]
        return

      # Listen to changes
      chrome.storage.onChanged.addListener (changes, namespace) =>
        switch namespace
          when 'sync'
            if M.STORE.BOX_SETTING of changes
              @settingProps = changes[M.STORE.BOX_SETTING].newValue
          when 'local'
            if M.STORE.DEBUG of changes
              @debug = changes[M.STORE.DEBUG].newValue
              log 'MailFred debugging is enabled' if @debug
            if M.STORE.EMAIL of changes
              @settingEmail = changes[M.STORE.EMAIL].newValue
        return

      return

    @storeLastVersion: (version) ->
      store = {}
      store[M.STORE.LAST_VERSION] = version
      chrome.storage.sync.set store, ->
        log 'Set the last used version to', version
        return
      return

    @getLastVersion: (resp) ->
      chrome.storage.sync.get M.STORE.LAST_VERSION, (items) ->
        resp items[M.STORE.LAST_VERSION]
        return
      return

    @isAuthorisationErrorPage: (contents) -> /reauth/i.test contents

    @isAuthorisationErrorResponse: (resp) ->
      (resp?.toLowerCase().indexOf "authorization") isnt -1

    isAuthorised: ->
      url = @getServiceURL() + M.SETUP_URL_SUFFIX
      log 'checking if the user authorised', url
      deferred = new $.Deferred
      error = ->
        log '...user is not authorised (yet/any more)'
        deferred.reject()
        return

      $.ajax
        url:      url
        dataType: 'json'
        cache:    false
        data:     format: 'json'
        success:  (data, textStatus, jqXHR) ->
          if data.success
            log '...user is still authorised'
            deferred.resolve()
          else
            error()
          return
        error:    (jqXHR, textStatus, errorThrown) ->
          error()
          return
      deferred.promise()

    firstInstall: (version) ->
      log 'first install', version
      @welcome()
      return

    upgradeInstall: (oldVersion, newVersion) ->
      log 'upgrade from', oldVersion, newVersion
      @isAuthorised().fail =>
        @gettingStarted()
        return
      return

    sameInstall: (version) ->
      log 'no version change', version
      @currentVersion = version
      return

    inConversation: ->
      @currentView is 'conversation'

    activateArchiveButton: ->
      return unless @inConversation()
      button = ($ M.GM_SEL.ARCHIVE_BUTTON).get 0
      if button
        Eventr.simulate button, 'mousedown'
        Eventr.simulate button, 'mouseup'
      return

    messageListener: (e) =>
      if e.source is window
        # We only accept messages from ourselves
        #log "event", e

        if e.data?.from is "GMAILR"
          # log 'Got Gmailr event: ', e.data.event.type
          evt = e.data.event
          switch evt.type
            when 'init'
            # GMailr is ready
              @currentGmail = evt.email
              # GMailUI.Breadcrumbs.add (__msg 'extName'), => @gettingStarted()

              # kick GMailr into debug mode?
              if @debug
                message =
                  from: 'MAILFRED'
                  type: 'debug.enable'
                window.postMessage message, "*"

            when 'viewThread'
            # User moves to previous or next convo
              @selectedConversationId = evt.args[0]
              @inject()
            when 'viewChanged'
            # User switches view (conversation <-> threads)
              @currentView = evt.args[0]
              log "User switched to #{@currentView} view"
              @inject()

      return

    checkVersion: ->
      # Get the extension version
      chrome.runtime.sendMessage {action: "version"}, (version) =>
        M.getLastVersion (lastVersion) =>
          unless lastVersion
            M.storeLastVersion version
            @firstInstall version
          else if lastVersion < version
            M.storeLastVersion version
            @upgradeInstall lastVersion, version
          else
            @sameInstall version
          return
        return
      return

    inject: ->
      return unless @inConversation()
      log 'Email address in settings', @settingEmail
      log 'Current Gmail window', @currentGmail

      @injectThread() if (not @settingEmail or not @currentGmail) or @currentGmail.trim() in @settingEmail.split /[, ]+/ig
      return

    getServiceURL: -> @url

    isPreviewPaneEnabled: ->
      ($ M.GM_SEL.PREVIEW_PANE_ENABLED).length > 0

    injectThread: ->
      log 'Injecting buttons in thread view'

      if @isPreviewPaneEnabled()
        # Preview pane is enabled
        sel = M.GM_SEL.PREVIEW_PANE_THREAD_BUTTON_BAR
      else
        # Preview pane is not enabled
        sel = M.GM_SEL.THREAD_BUTTON_BAR

      threads = ($ sel).filter (index) ->
        ($ ".#{M.CLS_THREAD}", @).length is 0

      if threads.length > 0
        after = threads.find M.GM_SEL.INSERT_AFTER
        bar = @composeButton()
        bar.addClass 'T-I'
        if after.length > 0 then after.after bar else threads.append bar
      return

    actionOps: [
          'unread'
          'star'
          'inbox'
          ]

    ucFirst: (str) ->
      str[0].toUpperCase() + str.substring(1).toLowerCase()

    getTexts: (key, time) ->
      i18nKey = @ucFirst key
      x = "menuTimePresetCloseFutureItem#{i18nKey}#{time}"
      [
        (__msg "#{x}Selected")
        (__msg x)
      ]

    composeButton: =>

      props =
        noanswer: false
        unread:   true
        star:     false
        inbox:    true
        archive:  true

      _.each props, (v, op) =>
        hasSetting = @settingProps and typeof @settingProps[op] isnt 'undefined'
        props[op] = !! @settingProps?[op] if hasSetting
        return

      schedule = (wen) =>
        pickerMenu.close()
        presetMenu.close()
        button.close()
        button.addClass M.CLS_LOADER
        props.when = wen
        (@onSchedule props).always ->
          button.removeClass M.CLS_LOADER
          return
        return

      isValid = =>
        valid = false
        for op in @actionOps
          valid |= props[op]
        valid = !!valid
        timeSection.toggle valid
        constraintSection.toggle valid
        errorSection.toggle !valid
        return

      propStoreFn = (checkbox, propName) =>
        checkbox.addOnChange (e, checked) =>
          props[propName] = checked
          toStore = {}
          toStore[M.STORE.BOX_SETTING] = props
          @settingProps = props
          chrome.storage.sync.set toStore, ->
            log 'Storing properties finished'
            return
          isValid()
        return

      presets = {}
      presets.minutes    = [5] if @debug
      presets.hours      = [4]
      presets.hours.unshift 2 if @debug
      presets.tomorrow   = [8,14]
      presets.days       = [2,7,14]
      presets.months     = [1] if @debug

      # UI

      bar = new GMailUI.ButtonBar
      bar.addClass M.CLS
      bar.addClass M.CLS_THREAD

      popup = new GMailUI.Popup
      popup.addClass M.CLS_POPUP

      popup.append new GMailUI.PopupLabel __msg 'menuMailActions'

      # Actions section

      actionSection = popup.append new GMailUI.Section
      actionSectionCheckboxes =
        unread: actionSection.append (new GMailUI.PopupCheckbox (__msg 'mailActionMarkUnread'),   props.unread,   '', (__msg 'mailActionMarkUnreadTitle'))
        star:  actionSection.append (new GMailUI.PopupCheckbox (__msg 'mailActionStar'),       props.star,   '', (__msg 'mailActionStarTitle'))
        inbox:  actionSection.append (new GMailUI.PopupCheckbox (__msg 'mailActionMoveToInbox'),   props.inbox,   '', (__msg 'mailActionMoveToInboxTitle'))

      _.each actionSectionCheckboxes, propStoreFn

      # Constraints section

      constraintSection = popup.append new GMailUI.Section
      constraintSection.append new GMailUI.Separator
      constraintSectionCheckboxes =
        noanswer:  constraintSection.append (new GMailUI.PopupCheckbox (__msg 'menuConstraintsNoAnswer'),    props.noanswer,  '', (__msg 'menuConstraintsNoAnswerTitle'))
        archive:  constraintSection.append (new GMailUI.PopupCheckbox (__msg 'menuAdditionalActionsArchive'), props.archive,  '', (__msg 'menuAdditionalActionsArchiveTitle'))

      _.each constraintSectionCheckboxes, propStoreFn


      presetMenu = new GMailUI.PopupMenu popup
      presetMenu.addClass M.CLS_MENU

      # Date picker
      pickerMenu = new GMailUI.PopupMenu popup
      pickerMenu.addClass M.CLS_PICKER

      picker = null
      pickerMenu.onShow = ->
        unless picker
          picker = new Pikaday
            bound: false
            format: __msg 'dateFormat'
            minDate: moment().add(1, 'day').toDate()
            maxDate: moment().add(1, 'year').toDate()
            onSelect: ->
              date = @getMoment()
              log 'schedule', date.format()
              schedule date.utc().valueOf()
              return
          pickerMenu.getElement().append picker.el
        return

      # Time section

      timeSection = popup.append new GMailUI.Section
      timeSection.append new GMailUI.Separator
      timeSection.append new GMailUI.PopupLabel __msg 'menuTime'

      timeSection.append   (new GMailUI.PopupMenuItem pickerMenu, (__msg 'menuTimePresetSpecifiedDate'),  '',  '',  true)
      timeSection.append new GMailUI.Separator

      # Presets

      sep = null
      _.each presets, (times, key) =>
        unless _.isEmpty times
          timeSection.append sep if sep
          _.each times, (time) =>
            timeFn = @generateTimeFn key
            [label, title] = @getTexts key, time
            item = timeSection.append new GMailUI.Button label, title
            item.on 'click', ->
              wen = timeFn time
              log "schedule: #{time}, #{key}: #{wen}"
              schedule wen
              return
            return
          sep = new GMailUI.Separator
        return

      button = bar.append new GMailUI.ButtonBarPopupButton popup, '', (__msg 'extName')
      errorSection = popup.append new GMailUI.ErrorSection __msg 'errorNoActionSpecified' # __msg 'errorNoTimeSpecified'

      isValid()

      bar.getElement()

    _delta: (offset) ->
      "delta:#{offset}"

    generateTimeFn: (unit) ->
      _1d = 24 * (_1h = 60 * (_1m = 60 * 1000))

      switch unit
        when 'minutes'
          (time) => @_delta (_1m * time)
        when 'hours'
          (time) => @_delta (_1h * time)
        when 'tomorrow'
          (hour) ->
            moment()
              .add(1, 'day')
              .hours(hour)
              .minutes(0)
              .seconds(0)
              .utc()
              .valueOf()
        when 'days'
          (time) => @_delta (_1d * time)
        when 'months'
          (month) ->
            moment().add(month, 'months').utc().valueOf()

    getMessageId: ->
      if @isPreviewPaneEnabled()
        id = @selectedConversationId
      else
        id = /\/([0-9a-f]{16})/i.exec window.location.hash
        id = id?[1]

      if id is null
        throw __msg 'errorNotWithinAConversation'
      id

    onSchedule: (props) =>
      try
        messageId = @getMessageId()
      catch e
        @onScheduleError null, null, e.toString(), ''
        return

      data =
        msgId: messageId
        when:  props.when
        version: @currentVersion

      data.markUnread = true              if !!props.unread
      data.starIt = true                  if !!props.star
      data.onlyIfNoAnswer = true          if !!props.noanswer
      data.moveToInbox = true             if !!props.inbox
      data.archiveAfterScheduling = true  if !!props.archive

      log 'scheduling mail...', data

      url = @getServiceURL() + M.SCHEDULE_SUFFIX

      success = =>
        chrome.runtime.sendMessage
          action:   'notification'
          icon:     'images/tie.svg'
          title:     __msg 'notificationScheduleSuccessTitle'
          message:   __msg 'notificationScheduleSuccess'
        @activateArchiveButton() if data.archiveAfterScheduling
        return

      error = (status, error, responseText) =>
        @onScheduleError status, data, error, responseText
        return

      ($.post url, data, null, 'json')
      .done (resp, textStatus, jqXHR) ->
        if resp.success
          success()
        else
          error textStatus, resp.error, jqXHR.responseText
        return
      .fail (jqXHR, textStatus, reason) ->
        error textStatus, reason, jqXHR.responseText
        return
      .promise()

    createDialog: (title, okButton, cancelButton) ->
      dialog = new GMailUI.ModalDialog title

      [okButtonLabel, okButtonTooltip] = okButton
      [cancelButtonLabel, cancelButtonTooltip] = cancelButton

      container = dialog.append new GMailUI.ModalDialog.Container

      footer = dialog.append new GMailUI.ModalDialog.Footer
      okButton = footer.append new GMailUI.ModalDialog.Button okButtonLabel, okButtonTooltip
      cancelButton = footer.append new GMailUI.ModalDialog.Button cancelButtonLabel, cancelButtonTooltip, 'cancel'

      [dialog, okButton, cancelButton, container, footer]

    welcome: ->
      extName = __msg 'extName'
      [dialog, okButton, cancelButton, container, footer] = @createDialog (__msg 'welcomeDialogTitle', extName), [(__msg 'welcomeDialogButtonOk'), (__msg 'welcomeDialogButtonOkTooltip')], [(__msg 'welcomeDialogButtonCancel'), (__msg 'welcomeDialogButtonCancelTooltip', extName)]

      welcomeDialogText = __msg 'welcomeDialogText', extName
      welcomeDialogText = welcomeDialogText.replace /\n/g, '<br/>'
      container.append  """
                <div style="text-align: justify;">
                  <img src="#{chrome.extension.getURL 'images/button_example.svg'}" data-tooltip="#{__msg 'welcomeDialogImageHint'}" alt="#{__msg 'welcomeDialogImageAlt'}" align="right" style="padding-left: 10px; padding-bottom: 10px; width: 115px; height: 73px;">
                  #{welcomeDialogText}
                </div>
                """

      okButton.on 'click', =>
        [authDialog, authOkButton, authCancelButton, authContainer, authFooter] = @gettingStartedDialog()
        container.replaceWith authContainer
        okButton.replaceWith authOkButton
        cancelButton.replaceWith authCancelButton
        dialog.title authDialog.title()

        authOkButton.on 'click', =>
          @openAuthWindow {}
          dialog.close()
          return

        authCancelButton.on 'click', dialog.close

      cancelButton.on 'click', dialog.close
      dialog.open()

    gettingStartedDialogContent: ->
      extName = __msg 'extName'
      img = chrome.extension.getURL 'images/authorize.svg'
      dialogText = __msg 'authorizeDialogText', extName
      dialogText = dialogText.replace /\n/g, '<br/>'
      """
      <div class="#{M.CLS_AUTH_TXT}">
        #{dialogText}
      </div>
      <div class="#{M.CLS_AUTH_IMG}">
        <img src="#{img}" data-tooltip="#{__msg 'authorizeDialogImageHint'}" alt="#{__msg 'authorizeDialogImageAlt'}">
      </div>
      """

    gettingStartedDialog: ->
      extName = __msg 'extName'
      [dialog, okButton, cancelButton, container, footer] = @createDialog (__msg 'authorizeDialogTitle', extName), [(__msg 'authorizeDialogButtonOk'), (__msg 'authorizeDialogButtonOkTooltip')], [(__msg 'authorizeDialogButtonCancel'), (__msg 'authorizeDialogButtonCancelTooltip', extName)]
      container.append @gettingStartedDialogContent()
      [dialog, okButton, cancelButton, container, footer]

    gettingStarted: (params) ->
      [dialog, okButton, cancelButton, container, footer] = @gettingStartedDialog()

      okButton.on 'click', =>
        @openAuthWindow params
        dialog.close()
        return

      cancelButton.on 'click', dialog.close

      dialog.open()

    openAuthWindow: (params) ->
      url = @getServiceURL() + M.SETUP_URL_SUFFIX
      if params
        query = $.param params
        url += "?#{query}"
      windowOptions =
        width: 500
        height: 500
        location: 0
        menubar: 0
        scrollbars: 0
        status: 0
        toolbar: 0
        resizable: 1
      w = window.open url, M.CLS, (($.param windowOptions).replace '&', ',')
      w.focus()
      return

    onScheduleError: (status, params, error, responseText) =>
      log 'There was an error', arguments

      errorCodeAvailable = (_.isObject error) and ('code' of error)
      if (errorCodeAvailable and error.code is'authMissing') or
      (status is 'parsererror' and M.isAuthorisationErrorPage responseText) or
      (M.isAuthorisationErrorResponse status)
        @gettingStarted params
      else
        getMessage = ->
          if errorCodeAvailable
            (__msg "notificationScheduleError#{error.code}")
          else
            (__msg 'notificationScheduleError', '' + new String error)

        chrome.runtime.sendMessage
          action:   'notification'
          icon:     'images/tie.svg'
          title:    __msg 'notificationScheduleErrorTitle'
          message:  getMessage()
      return

  mb = new M
  return

) jQuery, window if top.document is document