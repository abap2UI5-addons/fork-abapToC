CLASS zcl_zabap_toc_ui5 DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_app.

    "! Selection-screen state.
    TYPES:
      BEGIN OF ts_sel,
        target_system    TYPE ko013-tarsystem,
        transport        TYPE trkorr,
        owner            TYPE tr_as4user,
        description      TYPE as4text,
        include_released TYPE abap_bool,
        include_tocs     TYPE abap_bool,
        include_subs     TYPE abap_bool,
        desc_mode        TYPE string,      " '0'=ToC-style '1'=Original '2'=Custom (popup)
        ignore_version   TYPE abap_bool,
        max_wait_sec     TYPE i,
      END OF ts_sel.

    "! One result row in the UI table.
    TYPES:
      BEGIN OF ts_row,
        released_text  TYPE string,
        main_transport TYPE trkorr,
        transport      TYPE trkorr,
        type           TYPE trfunction,
        target_system  TYPE tr_target,
        owner          TYPE tr_as4user,
        creation_date  TYPE as4date,
        description    TYPE as4text,
        toc_number     TYPE trkorr,
        toc_status     TYPE string,
        highlight      TYPE string,         " None | Success | Warning | Error | Information
      END OF ts_row.
    TYPES tt_row TYPE STANDARD TABLE OF ts_row WITH EMPTY KEY.

    "! Visible state - bound to the view via _bind / _bind_edit.
    DATA s_sel       TYPE ts_sel.
    DATA t_report    TYPE tt_row.

    "! State for the "custom description" popup flow.
    DATA pending_action       TYPE string.
    DATA pending_transport    TYPE trkorr.
    DATA custom_description   TYPE string.

  PROTECTED SECTION.

    DATA client TYPE REF TO z2ui5_if_client.

    METHODS on_init.
    METHODS on_event.

    METHODS view_main.
    METHODS popup_description.

    METHODS gather_transports.

    METHODS execute_action
      IMPORTING action      TYPE string
                row         TYPE REF TO ts_row
                description TYPE string OPTIONAL.

    METHODS new_engine
      IMPORTING desc_mode     TYPE i
      RETURNING VALUE(engine) TYPE REF TO zcl_zabap_toc.

  PRIVATE SECTION.

ENDCLASS.



CLASS zcl_zabap_toc_ui5 IMPLEMENTATION.

  METHOD z2ui5_if_app~main.
    me->client = client.
    IF client->check_on_init( ).
      on_init( ).
    ELSEIF client->check_on_event( ).
      on_event( ).
    ENDIF.
  ENDMETHOD.


  METHOD on_init.
    " Defaults that mirror the original report's selection screen.
    s_sel = VALUE #(
      owner            = sy-uname
      max_wait_sec     = 30
      ignore_version   = abap_true
      desc_mode        = `0`
      include_released = abap_false
      include_tocs     = abap_false
      include_subs     = abap_false ).
    view_main( ).
  ENDMETHOD.


  METHOD on_event.

    DATA(event) = client->get( )-event.
    DATA lr_row     TYPE REF TO ts_row.
    DATA lv_trkorr  TYPE trkorr.

    CASE event.

      WHEN `SEARCH`.
        gather_transports( ).
        IF t_report IS INITIAL.
          client->message_toast_display( `No transports match the selection.` ).
        ENDIF.

      WHEN `RESET`.
        t_report = VALUE #( ).
        client->message_toast_display( `Cleared.` ).

      WHEN `TOC_C` OR `TOC_CR` OR `TOC_CRI`.
        " event_arg(1) carries the transport number of the clicked row
        lv_trkorr = client->get_event_arg( 1 ).
        READ TABLE t_report WITH KEY transport = lv_trkorr REFERENCE INTO lr_row.
        IF sy-subrc <> 0.
          client->message_toast_display( `Row not found.` ).
          RETURN.
        ENDIF.

        IF s_sel-desc_mode = `2`. " custom
          " Custom description: capture text via popup, then continue.
          pending_action     = event.
          pending_transport  = lv_trkorr.
          custom_description = CONV string( lr_row->description ).
          popup_description( ).
          RETURN.
        ENDIF.

        execute_action( action = event row = lr_row ).

      WHEN `DESC_OK`.
        client->popup_destroy( ).
        READ TABLE t_report WITH KEY transport = pending_transport REFERENCE INTO lr_row.
        IF sy-subrc = 0.
          execute_action(
            action      = pending_action
            row         = lr_row
            description = custom_description ).
        ENDIF.
        CLEAR: pending_action, pending_transport, custom_description.

      WHEN `DESC_CANCEL`.
        client->popup_destroy( ).
        CLEAR: pending_action, pending_transport, custom_description.

      WHEN OTHERS.
        " ignore
    ENDCASE.

    view_main( ).

  ENDMETHOD.


  METHOD gather_transports.

    DATA lt_report TYPE tt_row.

    " Equivalent to ZCL_ZABAP_TOC_REPORT->gather_transports, but with single-value
    " filters (no SELECT-OPTIONS) - 'description' is matched with LIKE so '*' wildcards work.
    DATA(lv_descr_pattern) = COND as4text(
      WHEN s_sel-description IS INITIAL THEN '%'
      ELSE replace( val = s_sel-description sub = '*' with = '%' occ = 0 ) ).

    SELECT FROM e070
                LEFT JOIN e07t ON e07t~trkorr = e070~trkorr
                LEFT JOIN e070 AS sup ON sup~trkorr = e070~strkorr
      FIELDS
        CASE WHEN e070~trstatus = 'L' OR e070~trstatus = 'D' THEN @space
             ELSE 'X' END AS released_flag,
        CASE WHEN sup~trkorr IS NULL THEN e070~trkorr ELSE sup~trkorr END AS main_transport,
        e070~trkorr        AS transport,
        e070~trfunction    AS type,
        CASE WHEN e070~tarsystem <> @space THEN e070~tarsystem ELSE sup~tarsystem END AS target_system,
        e070~as4user       AS owner,
        e070~as4date       AS creation_date,
        e07t~as4text       AS description
      WHERE ( @s_sel-transport = @space OR e070~trkorr  = @s_sel-transport )
        AND ( @s_sel-owner     = @space OR e070~as4user = @s_sel-owner     )
        AND ( @s_sel-description = @space OR e07t~as4text LIKE @lv_descr_pattern )
        AND ( @s_sel-include_subs     = @abap_true OR e070~strkorr = @space )
        AND ( @s_sel-include_released = @abap_true
              OR e070~trstatus IN ( 'L', 'D' )
              OR sup~trstatus  IN ( 'L', 'D' ) )
        AND ( @s_sel-include_tocs     = @abap_true OR e070~trfunction <> 'T' )
      ORDER BY e070~trkorr DESCENDING, e070~as4date DESCENDING
      INTO TABLE @DATA(lt_raw).

    " Build display rows
    LOOP AT lt_raw REFERENCE INTO DATA(lr_raw).
      DATA(ls_row) = VALUE ts_row(
        main_transport = lr_raw->main_transport
        transport      = lr_raw->transport
        type           = lr_raw->type
        target_system  = lr_raw->target_system
        owner          = lr_raw->owner
        creation_date  = lr_raw->creation_date
        description    = lr_raw->description
        released_text  = COND #( WHEN lr_raw->released_flag = 'X' THEN 'Released' ELSE 'Open' )
        highlight      = `None` ).
      APPEND ls_row TO lt_report.
    ENDLOOP.

    " Deduplicate by transport (same as the original)
    SORT lt_report BY transport.
    DELETE ADJACENT DUPLICATES FROM lt_report COMPARING transport.
    SORT lt_report BY creation_date DESCENDING transport DESCENDING.

    t_report = lt_report.

  ENDMETHOD.


  METHOD execute_action.

    DATA(target_system) = COND tr_target(
      WHEN s_sel-target_system IS INITIAL THEN row->target_system
      ELSE s_sel-target_system ).

    " For "custom" description we feed the engine the user-typed text and use the
    " "original" strategy, which means the engine just passes the description through.
    DATA(lv_desc_mode_int) = CONV i( s_sel-desc_mode ).
    DATA(desc_mode_eff) = COND i(
      WHEN lv_desc_mode_int = zcl_zabap_toc_description=>c_toc_description-custom
        THEN zcl_zabap_toc_description=>c_toc_description-original
      ELSE lv_desc_mode_int ).

    DATA(engine) = new_engine( desc_mode_eff ).

    DATA(source_description) = COND string(
      WHEN description IS NOT INITIAL THEN description
      ELSE CONV string( row->description ) ).

    CLEAR row->highlight.

    TRY.
        CASE action.

          WHEN `TOC_C`.
            row->toc_number = engine->create(
              source_transport   = row->transport
              source_description = source_description
              target_system      = target_system ).
            row->toc_status = `Created`.
            row->highlight  = `Success`.

          WHEN `TOC_CR`.
            row->toc_number = engine->create(
              source_transport   = row->transport
              source_description = source_description
              target_system      = target_system ).
            engine->release( row->toc_number ).
            row->toc_status = `Created + Released`.
            row->highlight  = `Success`.

          WHEN `TOC_CRI`.
            row->toc_number = engine->create(
              source_transport   = row->transport
              source_description = source_description
              target_system      = target_system ).
            engine->release( row->toc_number ).
            DATA(rc) = CONV i( engine->import(
              toc                  = row->toc_number
              target_system        = target_system
              max_wait_time_in_sec = s_sel-max_wait_sec
              ignore_version       = s_sel-ignore_version ) ).
            row->toc_status = |Imported (rc={ rc })|.
            row->highlight  = COND #( WHEN rc = 0 THEN `Success`
                                      WHEN rc = 4 THEN `Warning`
                                      ELSE             `Error` ).
        ENDCASE.

      CATCH zcx_zabap_user_cancel.
        row->toc_status = `Cancelled`.
        row->highlight  = `Error`.

      CATCH zcx_zabap_exception INTO DATA(lx).
        row->toc_status = lx->get_text( ).
        row->highlight  = `Error`.

      CATCH cx_root INTO DATA(lx_root).
        row->toc_status = lx_root->get_text( ).
        row->highlight  = `Error`.
    ENDTRY.

    client->message_toast_display( |{ row->transport }: { row->toc_status }| ).

  ENDMETHOD.


  METHOD new_engine.
    DATA(desc) = NEW zcl_zabap_toc_description( desc_mode ).
    engine = NEW zcl_zabap_toc( desc ).
  ENDMETHOD.


  METHOD view_main.

    DATA(view) = z2ui5_cl_ui5_view_builder=>factory( 
                     )->ele( n = `View` ns = `mvc` 
                     )->a( n = `xmlns` v = `sap.m` 
                     )->a( n = `xmlns:mvc` v = `sap.ui.core.mvc` 
                     )->a( n = `xmlns:core` v = `sap.ui.core` 
                     )->a( n = `xmlns:form` v = `sap.ui.layout.form` 
                     )->a( n = `xmlns:layout` v = `sap.ui.layout` 
                     )->a( n = `displayBlock` v = `true` 
                     )->a( n = `height` v = `100%` ).
    DATA(page) = view->ele( `Shell` 
                     )->ele( `Page` 
                     )->a( n = `title` v = `abap2UI5 - Transport of Copies` 
                     )->a( n = `showNavButton` b = abap_false ).

    " ---------- Selection block ----------
    DATA(form) = page->ele( n = `Grid` ns = `layout` 
                     )->a( n = `defaultSpan` v = `L8 M10 S12` 
                     )->ele( n = `content` ns = `layout` 
                     )->ele( n = `SimpleForm` ns = `form` 
                     )->a( n = `title` v = `Selection` 
                     )->a( n = `editable` b = abap_true 
                     )->ele( n = `content` ns = `form` ).

    form->tag( `Title` 
        )->a( n = `text` v = `Target System` ).
    form->tag( `Label` 
        )->a( n = `text` v = `Target System / Group` 
        )->tag( `Input` 
        )->a( n = `value` v = client->_bind_edit( s_sel-target_system ) 
        )->a( n = `placeholder` v = `e.g. Q01 or /MY_GRP/` ).

    form->tag( `Title` 
        )->a( n = `text` v = `Filters` ).
    form->tag( `Label` 
        )->a( n = `text` v = `Transport` 
        )->tag( `Input` 
        )->a( n = `value` v = client->_bind_edit( s_sel-transport ) 
        )->a( n = `placeholder` v = `single TR number, blank = all` ).

    form->tag( `Label` 
        )->a( n = `text` v = `Owner` 
        )->tag( `Input` 
        )->a( n = `value` v = client->_bind_edit( s_sel-owner ) 
        )->a( n = `placeholder` v = `user name, blank = all` ).

    form->tag( `Label` 
        )->a( n = `text` v = `Description (LIKE, * wildcard)` 
        )->tag( `Input` 
        )->a( n = `value` v = client->_bind_edit( s_sel-description ) 
        )->a( n = `placeholder` v = `*foo*` ).

    form->tag( `Label` 
        )->a( n = `text` v = `Include released transports` 
        )->tag( `CheckBox` 
        )->a( n = `selected` v = client->_bind_edit( s_sel-include_released ) ).

    form->tag( `Label` 
        )->a( n = `text` v = `Include ToCs` 
        )->tag( `CheckBox` 
        )->a( n = `selected` v = client->_bind_edit( s_sel-include_tocs ) ).

    form->tag( `Label` 
        )->a( n = `text` v = `Include subtransports` 
        )->tag( `CheckBox` 
        )->a( n = `selected` v = client->_bind_edit( s_sel-include_subs ) ).

    form->tag( `Title` 
        )->a( n = `text` v = `Options` ).
    form->tag( `Label` 
        )->a( n = `text` v = `Description style` 
        )->ele( `SegmentedButton` 
        )->a( n = `selectedKey` v = client->_bind_edit( s_sel-desc_mode ) 
        )->ele( `items` 
        )->tag( `SegmentedButtonItem` 
        )->a( n = `key` v = `0` 
        )->a( n = `text` v = `ToC-style` 
        )->tag( `SegmentedButtonItem` 
        )->a( n = `key` v = `1` 
        )->a( n = `text` v = `Original` 
        )->tag( `SegmentedButtonItem` 
        )->a( n = `key` v = `2` 
        )->a( n = `text` v = `Custom (popup)` ).

    form->tag( `Label` 
        )->a( n = `text` v = `Max wait time on import (sec)` 
        )->tag( `Input` 
        )->a( n = `value` v = client->_bind_edit( s_sel-max_wait_sec ) 
        )->a( n = `type` v = `Number` ).

    form->tag( `Label` 
        )->a( n = `text` v = `Ignore version on import` 
        )->tag( `CheckBox` 
        )->a( n = `selected` v = client->_bind_edit( s_sel-ignore_version ) ).

    " ---------- Action toolbar (search/reset) ----------
    page->ele( `footer` 
        )->ele( `OverflowToolbar` 
        )->tag( `ToolbarSpacer` 
        )->tag( `Button` 
        )->a( n = `text` v = `Reset` 
        )->a( n = `press` v = client->_event( `RESET` ) 
        )->a( n = `icon` v = `sap-icon://clear-all` 
        )->tag( `Button` 
        )->a( n = `text` v = `Search` 
        )->a( n = `press` v = client->_event( `SEARCH` ) 
        )->a( n = `type` v = `Emphasized` 
        )->a( n = `icon` v = `sap-icon://search` ).

    " ---------- Result table ----------
    DATA(tab) = page->ele( `Table` 
                    )->a( n = `headerText` v = `Transports` 
                    )->a( n = `growing` b = abap_true 
                    )->a( n = `growingThreshold` v = `100` 
                    )->a( n = `mode` v = `None` 
                    )->a( n = `items` v = client->_bind( t_report ) ).

    tab->ele( `columns` 
        )->ele( `Column` 
        )->a( n = `width` v = `6rem` 
        )->tag( `Text` 
        )->a( n = `text` v = `Status` 
        )->end( 
        )->ele( `Column` 
        )->a( n = `width` v = `9rem` 
        )->tag( `Text` 
        )->a( n = `text` v = `Transport` 
        )->end( 
        )->ele( `Column` 
        )->a( n = `width` v = `4rem` 
        )->tag( `Text` 
        )->a( n = `text` v = `Type` 
        )->end( 
        )->ele( `Column` 
        )->a( n = `width` v = `8rem` 
        )->tag( `Text` 
        )->a( n = `text` v = `Target` 
        )->end( 
        )->ele( `Column` 
        )->a( n = `width` v = `8rem` 
        )->tag( `Text` 
        )->a( n = `text` v = `Owner` 
        )->end( 
        )->ele( `Column` 
        )->a( n = `width` v = `7rem` 
        )->tag( `Text` 
        )->a( n = `text` v = `Created` 
        )->end( 
        )->ele( `Column` 
        )->a( n = `width` v = `20rem` 
        )->tag( `Text` 
        )->a( n = `text` v = `Description` 
        )->end( 
        )->ele( `Column` 
        )->a( n = `width` v = `4rem` 
        )->a( n = `hAlign` v = `Center` 
        )->tag( `Text` 
        )->a( n = `text` v = `ToC` 
        )->end( 
        )->ele( `Column` 
        )->a( n = `width` v = `4rem` 
        )->a( n = `hAlign` v = `Center` 
        )->tag( `Text` 
        )->a( n = `text` v = `+Rel` 
        )->end( 
        )->ele( `Column` 
        )->a( n = `width` v = `4rem` 
        )->a( n = `hAlign` v = `Center` 
        )->tag( `Text` 
        )->a( n = `text` v = `+Imp` 
        )->end( 
        )->ele( `Column` 
        )->a( n = `width` v = `9rem` 
        )->tag( `Text` 
        )->a( n = `text` v = `New ToC` 
        )->end( 
        )->ele( `Column` 
        )->a( n = `width` v = `15rem` 
        )->tag( `Text` 
        )->a( n = `text` v = `Result` 
        )->end( ).

    DATA(cells) = tab->ele( `items` 
                      )->ele( `ColumnListItem` 
                      )->a( n = `highlight` v = `{HIGHLIGHT}` 
                      )->ele( `cells` ).
    cells->tag( `Text` 
        )->a( n = `text` v = `{RELEASED_TEXT}` ).
    cells->tag( `Text` 
        )->a( n = `text` v = `{TRANSPORT}` ).
    cells->tag( `Text` 
        )->a( n = `text` v = `{TYPE}` ).
    cells->tag( `Text` 
        )->a( n = `text` v = `{TARGET_SYSTEM}` ).
    cells->tag( `Text` 
        )->a( n = `text` v = `{OWNER}` ).
    cells->tag( `Text` 
        )->a( n = `text` v = `{CREATION_DATE}` ).
    cells->tag( `Text` 
        )->a( n = `text` v = `{DESCRIPTION}` ).

    " Three icon buttons replacing the SALV hotspot columns
    cells->tag( `Button` 
        )->a( n = `icon` v = `sap-icon://create` 
        )->a( n = `tooltip` v = `Create ToC` 
        )->a( n = `type` v = `Transparent` 
        )->a( n = `press` v = client->_event( val = `TOC_C`
                                 t_arg = VALUE #( ( `${TRANSPORT}` ) ) ) ).
    cells->tag( `Button` 
        )->a( n = `icon` v = `sap-icon://activate` 
        )->a( n = `tooltip` v = `Create + Release ToC` 
        )->a( n = `type` v = `Transparent` 
        )->a( n = `press` v = client->_event( val = `TOC_CR`
                                 t_arg = VALUE #( ( `${TRANSPORT}` ) ) ) ).
    cells->tag( `Button` 
        )->a( n = `icon` v = `sap-icon://process` 
        )->a( n = `tooltip` v = `Create + Release + Import ToC` 
        )->a( n = `type` v = `Transparent` 
        )->a( n = `press` v = client->_event( val = `TOC_CRI`
                                 t_arg = VALUE #( ( `${TRANSPORT}` ) ) ) ).

    cells->tag( `Text` 
        )->a( n = `text` v = `{TOC_NUMBER}` ).
    cells->tag( `Text` 
        )->a( n = `text` v = `{TOC_STATUS}` ).

    client->view_display( view->stringify( ) ).

  ENDMETHOD.


  METHOD popup_description.

    DATA(popup) = z2ui5_cl_ui5_view_builder=>factory( 
                      )->ele( n = `FragmentDefinition` ns = `core` 
                      )->a( n = `xmlns` v = `sap.m` 
                      )->a( n = `xmlns:core` v = `sap.ui.core` 
                      )->a( n = `xmlns:form` v = `sap.ui.layout.form` 
                      )->a( n = `xmlns:layout` v = `sap.ui.layout` ).
    DATA(dialog) = popup->ele( `Dialog` 
                       )->a( n = `title` v = |Description for new ToC ({ pending_transport })| ).

    dialog->ele( n = `SimpleForm` ns = `form` 
        )->a( n = `editable` b = abap_true 
        )->ele( n = `content` ns = `form` 
        )->tag( `Label` 
        )->a( n = `text` v = `Description for the Transport of Copies` 
        )->tag( `TextArea` 
        )->a( n = `value` v = client->_bind_edit( custom_description ) 
        )->a( n = `rows` v = `4` 
        )->a( n = `width` v = `40rem` 
        )->a( n = `placeholder` v = `Enter the description that should appear on the new ToC` ).

    dialog->ele( `buttons` 
        )->tag( `Button` 
        )->a( n = `text` v = `Cancel` 
        )->a( n = `press` v = client->_event( `DESC_CANCEL` ) 
        )->a( n = `type` v = `Reject` 
        )->tag( `Button` 
        )->a( n = `text` v = `Confirm` 
        )->a( n = `press` v = client->_event( `DESC_OK` ) 
        )->a( n = `type` v = `Emphasized` ).

    client->popup_display( popup->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
