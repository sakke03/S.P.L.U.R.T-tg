/// Global list of ALL loadout datums instantiated.
/// Loadout datums are created by loadout categories.
GLOBAL_LIST_EMPTY(all_loadout_datums)

/// Global list of all loadout categories
/// Doesn't really NEED to be a global but we need to init this early for preferences,
/// as the categories instantiate all the loadout datums
GLOBAL_LIST_INIT(all_loadout_categories, init_loadout_categories())

/// Inits the global list of loadout category singletons
/// Also inits loadout item singletons
/proc/init_loadout_categories()
	var/list/loadout_categories = list()
	for(var/category_type in subtypesof(/datum/loadout_category))
		loadout_categories += new category_type()

	sortTim(loadout_categories, /proc/cmp_loadout_categories)
	return loadout_categories

/proc/cmp_loadout_categories(datum/loadout_category/A, datum/loadout_category/B)
	var/a_order = A::tab_order
	var/b_order = B::tab_order
	if(a_order == b_order)
		return cmp_text_asc(A::category_name, B::category_name)
	return cmp_numeric_asc(a_order, b_order)

/**
 * # Loadout item datum
 *
 * Singleton that holds all the information about each loadout items, and how to equip them.
 */
/datum/loadout_item
	/// The category of the loadout item. Set automatically in New
	VAR_FINAL/datum/loadout_category/category
	/// Displayed name of the loadout item.
	/// Defaults to the item's name if unset.
	var/name
	/// Title of a group that this item will be bundled under
	/// Defaults to parent category's title if unset
	var/group = null
	/// Whether this item has greyscale support.
	/// Only works if the item is compatible with the GAGS system of coloring.
	/// Set automatically to TRUE for all items that have the flag [IS_PLAYER_COLORABLE_1].
	/// If you really want it to not be colorable set this to [DONT_GREYSCALE]
	var/can_be_greyscale = FALSE
	/// Whether this item can be renamed.
	/// I recommend you apply this sparingly becuase it certainly can go wrong (or get reset / overridden easily)
	var/can_be_named = TRUE // SKYRAT EDIT
	/// Whether this item can be reskinned.
	/// Only works if the item has a "unique reskin" list set.
	var/can_be_reskinned = FALSE
	/// The abstract parent of this loadout item, to determine which items to not instantiate
	var/abstract_type = /datum/loadout_item
	/// The actual item path of the loadout item.
	var/obj/item/item_path
	/// Icon file (DMI) for the UI to use for preview icons.
	/// Set automatically if null
	var/ui_icon
	/// Icon state for the UI to use for preview icons.
	/// Set automatically if null
	var/ui_icon_state
	/// Reskin options of this item if it can be reskinned.
	VAR_FINAL/list/cached_reskin_options

	// BUBBER EDIT ADDITION START
	/// If set, it's a list containing ckeys which only can get the item
	var/list/ckeywhitelist
	/// If set, is a list of job names of which can get the loadout item
	var/list/restricted_roles
	/// If set, is a list of job names of which can't get the loadout item
	var/list/blacklisted_roles
	/// If set, is a list of species which can get the loadout item
	var/list/restricted_species
	/// Whether the item is restricted to supporters
	var/donator_only
	/// Whether the item requires a specific season in order to be available
	var/required_season = null
	/// If the item won't appear when the ERP config is disabled
	var/erp_item = FALSE
	// BUBBER EDIT END

/datum/loadout_item/New(category)
	src.category = category

	if(can_be_greyscale == DONT_GREYSCALE)
		can_be_greyscale = FALSE
	else if((item_path::flags_1 & IS_PLAYER_COLORABLE_1) && item_path::greyscale_config && item_path::greyscale_colors)
		can_be_greyscale = TRUE

	if(isnull(name))
		name = item_path::name

	if(isnull(ui_icon) && isnull(ui_icon_state))
		ui_icon = item_path::icon_preview || item_path::icon
		ui_icon_state = item_path::icon_state_preview || item_path::icon_state

	if(can_be_reskinned)
		var/obj/item/dummy_item = new item_path()
		if(!length(dummy_item.unique_reskin))
			can_be_reskinned = FALSE
			stack_trace("Loadout item [item_path] has can_be_reskinned set to TRUE but has no unique reskins.")
		else
			cached_reskin_options = dummy_item.unique_reskin.Copy()
		qdel(dummy_item)

	// SKYRAT EDIT ADDITION
	// Let's sanitize in case somebody inserted the player's byond name instead of ckey in canonical form
	if(ckeywhitelist)
		for (var/i = 1, i <= length(ckeywhitelist), i++)
			ckeywhitelist[i] = ckey(ckeywhitelist[i])
	// SKYRAT EDIT END

/datum/loadout_item/Destroy(force, ...)
	if(force)
		stack_trace("QDEL called on loadout item [type]. This shouldn't ever happen. (Use FORCE if necessary.)")
		return QDEL_HINT_LETMELIVE

	GLOB.all_loadout_datums -= item_path
	return ..()

/**
 * Takes in an action from a loadout manager and applies it
 *
 * Useful for subtypes of loadout items with unique actions
 *
 * Return TRUE to force an update to the UI / character preview
 */
/datum/loadout_item/proc/handle_loadout_action(datum/preference_middleware/loadout/manager, mob/user, action, params)
	SHOULD_CALL_PARENT(TRUE)

	switch(action)
		if("select_color")
			if(can_be_greyscale)
				return set_item_color(manager, user)

		if("set_name")
			if(can_be_named)
		// SKYRAT EDIT BEGIN - Description
				return set_name(manager, user, INFO_NAMED)

		if("set_desc")
			if(can_be_named)
				return set_name(manager, user, INFO_DESCRIBED)
		// SKYRAT EDIT END

		if("set_skin")
			return set_skin(manager, user, params)

	return TRUE

/// Opens up the GAGS editing menu.
/datum/loadout_item/proc/set_item_color(datum/preference_middleware/loadout/manager, mob/user)
	if(manager.menu)
		return FALSE

	var/list/loadout = manager.get_current_loadout() // BUBBER EDIT: Multiple loadout presets: ORIGINAL: var/list/loadout = manager.preferences.read_preference(/datum/preference/loadout)
	var/list/allowed_configs = list()
	if(initial(item_path.greyscale_config))
		allowed_configs += "[initial(item_path.greyscale_config)]"
	if(initial(item_path.greyscale_config_worn))
		allowed_configs += "[initial(item_path.greyscale_config_worn)]"
	if(initial(item_path.greyscale_config_inhand_left))
		allowed_configs += "[initial(item_path.greyscale_config_inhand_left)]"
	if(initial(item_path.greyscale_config_inhand_right))
		allowed_configs += "[initial(item_path.greyscale_config_inhand_right)]"

	var/datum/greyscale_modify_menu/menu = new(
		manager,
		user,
		allowed_configs,
		CALLBACK(src, PROC_REF(set_slot_greyscale), manager),
		starting_icon_state = initial(item_path.icon_state),
		starting_config = initial(item_path.greyscale_config),
		starting_colors = loadout?[item_path]?[INFO_GREYSCALE] || initial(item_path.greyscale_colors),
	)

	manager.register_greyscale_menu(menu)
	menu.ui_interact(user)
	return TRUE

/// Callback for GAGS menu to set this item's color.
/datum/loadout_item/proc/set_slot_greyscale(datum/preference_middleware/loadout/manager, datum/greyscale_modify_menu/open_menu)
	if(!istype(open_menu))
		CRASH("set_slot_greyscale called without a greyscale menu!")

	var/list/loadout = manager.get_current_loadout() // BUBBER EDIT: Multiple loadout presets: ORIGINAL: var/list/loadout = manager.preferences.read_preference(/datum/preference/loadout)
	if(!loadout?[item_path])
		return FALSE

	var/list/colors = open_menu.split_colors
	if(!colors)
		return FALSE

	loadout[item_path][INFO_GREYSCALE] = colors.Join("")
	manager.save_current_loadout(loadout) // BUBBER EDIT: Multiple loadout presets: ORIGINAL: manager.preferences.update_preference(GLOB.preference_entries[/datum/preference/loadout], loadout)
	return TRUE // update UI

/// Sets the name of the item.
// SKYRAT EDIT BEGIN - Adds descriptions with minimal copypaste
// Generally, if this conflicts, name_slot is to be put anywhere where INFO_NAMED appears in tgcode
/datum/loadout_item/proc/set_name(datum/preference_middleware/loadout/manager, mob/user, name_slot = INFO_NAMED)
	var/isname = (name_slot == INFO_NAMED)
	var/list/loadout = manager.get_current_loadout() // BUBBER EDIT: Multiple loadout presets: ORIGINAL: var/list/loadout = manager.preferences.read_preference(/datum/preference/loadout)
	var/input_name = tgui_input_text(
		user = user,
		message = "What [isname ? "name" : "description"] do you want to give the [name]? Leave blank to clear.",
		title = "[name] [isname ? "name" : "description"]",
		default = loadout?[item_path]?[name_slot], // plop in existing name (if any)
		max_length = isname ? MAX_NAME_LEN : MAX_DESC_LEN,
	)
	if(QDELETED(src) || QDELETED(user) || QDELETED(manager) || QDELETED(manager.preferences))
		return FALSE

	loadout = manager.get_current_loadout() // BUBBER EDIT: Multiple loadout presets: ORIGINAL: loadout = manager.preferences.read_preference(/datum/preference/loadout) // Make sure no shenanigans happened
	if(!loadout?[item_path])
		return FALSE

	if(input_name)
		loadout[item_path][name_slot] = input_name
	else if(input_name == "")
		loadout[item_path] -= name_slot

	manager.save_current_loadout(loadout) // BUBBER EDIT: Multiple loadout presets: ORIGINAL: manager.preferences.update_preference(GLOB.preference_entries[/datum/preference/loadout], loadout)
	return FALSE // no update needed
// SKYRAT EDIT END

/// Used for reskinning an item to an alt skin.
/datum/loadout_item/proc/set_skin(datum/preference_middleware/loadout/manager, mob/user, params)
	if(!can_be_reskinned)
		return FALSE

	var/reskin_to = params["skin"]
	if(!cached_reskin_options[reskin_to])
		return FALSE

	var/list/loadout = manager.get_current_loadout() // BUBBER EDIT: Multiple loadout presets: ORIGINAL: var/list/loadout = manager.preferences.read_preference(/datum/preference/loadout)
	if(!loadout?[item_path])
		return FALSE

	loadout[item_path][INFO_RESKIN] = reskin_to
	manager.save_current_loadout(loadout) // BUBBER EDIT: Multiple loadout presets: ORIGINAL: manager.preferences.update_preference(GLOB.preference_entries[/datum/preference/loadout], loadout)
	return TRUE // always update UI

/**
 * Place our [item_path] into the passed [outfit].
 *
 * By default, just adds the item into the outfit's backpack contents, if non-visual.
 *
 * Arguments:
 * * outfit - The outfit we're equipping our items into.
 * * equipper - If we're equipping out outfit onto a mob at the time, this is the mob it is equipped on. Can be null.
 * * visual - If TRUE, then our outfit is only for visual use (for example, a preview).
 */
/datum/loadout_item/proc/insert_path_into_outfit(datum/outfit/outfit, mob/living/carbon/human/equipper, visuals_only = FALSE, loadout_placement_preference) // SKYRAT EDIT CHANGE - Added loadout_placement_preference
	if(!visuals_only)
		LAZYADD(outfit.backpack_contents, item_path)

/**
 * Called When the item is equipped on [equipper].
 *
 * At this point the item is in the mob's contents
 *
 * Arguments:
 * * preference_source - the datum/preferences our loadout item originated from - cannot be null
 * * equipper - the mob we're equipping this item onto
 * * visuals_only - whether or not this is only concerned with visual things (not backpack, not renaming, etc)
 * * preference_list - what the raw loadout list looks like in the preferences
 *
 * Return a bitflag of slot flags to update
 */
/datum/loadout_item/proc/on_equip_item(
	obj/item/equipped_item,
	datum/preferences/preference_source,
	list/preference_list,
	mob/living/carbon/human/equipper,
	visuals_only = FALSE,
)
	if(isnull(equipped_item))
		return NONE

	if(!visuals_only)
		ADD_TRAIT(equipped_item, TRAIT_ITEM_OBJECTIVE_BLOCKED, TRAIT_SOURCE_LOADOUT)

	var/list/item_details = preference_list[item_path]
	var/update_flag = NONE

	if(can_be_greyscale && item_details?[INFO_GREYSCALE])
		equipped_item.set_greyscale(item_details[INFO_GREYSCALE])
		update_flag |= equipped_item.slot_flags

	// SKYRAT EDIT BEGIN - DESCRIPTIONS~
	if(can_be_named && !visuals_only)
		var/renamed = 0
		if(item_details?[INFO_NAMED])
			equipped_item.name = trim(item_details[INFO_NAMED], PREVENT_CHARACTER_TRIM_LOSS(MAX_NAME_LEN))
			renamed = 1
		if(item_details?[INFO_DESCRIBED])
			equipped_item.desc = trim(item_details[INFO_DESCRIBED], PREVENT_CHARACTER_TRIM_LOSS(MAX_DESC_LEN))
			renamed = 1
		if(renamed)
			ADD_TRAIT(equipped_item, TRAIT_WAS_RENAMED, TRAIT_SOURCE_LOADOUT)
			equipped_item.AddElement(/datum/element/examined_when_worn)
			SEND_SIGNAL(equipped_item, COMSIG_NAME_CHANGED)
	// SKYRAT EDIT END

	if(can_be_reskinned && item_details?[INFO_RESKIN])
		var/skin_chosen = item_details[INFO_RESKIN]
		if(skin_chosen in equipped_item.unique_reskin)
			equipped_item.current_skin = skin_chosen
			equipped_item.icon_state = equipped_item.unique_reskin[skin_chosen]
			if(istype(equipped_item, /obj/item/clothing/accessory))
				// Snowflake handing for accessories, because we need to update the thing it's attached to instead
				if(isclothing(equipped_item.loc))
					var/obj/item/clothing/under/attached_to = equipped_item.loc
					attached_to.update_accessory_overlay()
					update_flag |= (ITEM_SLOT_OCLOTHING|ITEM_SLOT_ICLOTHING)
			else
				update_flag |= equipped_item.slot_flags

		else
			// Not valid, update the preference
			item_details -= INFO_RESKIN
			preference_source.write_preference(GLOB.preference_entries[/datum/preference/loadout], preference_list)

	return update_flag

/**
 * Returns a formatted list of data for this loadout item.
 */
/datum/loadout_item/proc/to_ui_data() as /list
	SHOULD_CALL_PARENT(TRUE)

	var/list/formatted_item = list()
	var/list/information = list()
	var/list/fetched_info = get_item_information()
	for (var/icon_name in fetched_info)
		information += list(list(
			"icon" = icon_name,
			"tooltip" = fetched_info[icon_name]
		))

	formatted_item["name"] = name
	formatted_item["group"] = group || category.category_name
	formatted_item["path"] = item_path
	formatted_item["information"] = information
	formatted_item["buttons"] = get_ui_buttons()
	formatted_item["reskins"] = get_reskin_options()
	formatted_item["icon"] = ui_icon
	formatted_item["icon_state"] = ui_icon_state
	formatted_item["ckey_whitelist"] = ckeywhitelist // BUBBER EDIT ADDITION: Filter ckey-locked items

	return formatted_item

/**
 * Returns a list of information to display about this item in the loadout UI.
 * Icon -> tooltip displayed when its hovered over
 */
/datum/loadout_item/proc/get_item_information() as /list
	SHOULD_CALL_PARENT(TRUE)

	// Mothblocks is hellbent on recolorable and reskinnable being only tooltips for items for visual clarity, so ask her before changing these
	var/list/displayed_text = list()
	if(can_be_greyscale)
		displayed_text[FA_ICON_PALETTE] = "Recolorable"

	if(can_be_reskinned)
		displayed_text[FA_ICON_SWATCHBOOK] = "Reskinnable"

	// SKYRAT EDIT ADDITION
	if(donator_only)
		displayed_text[FA_ICON_MONEY_BILL] = "Donator only"

	if(ckeywhitelist)
		displayed_text[FA_ICON_LOCK] = "Player Whitelist: [ckeywhitelist.Join(", ")]"

	if(restricted_roles || blacklisted_roles)
		var/list/tooltip_text = list()
		if(restricted_roles)
			tooltip_text += "Job Whitelist: [restricted_roles.Join(", ")]"
		if(blacklisted_roles)
			tooltip_text += "Job Blacklist: [blacklisted_roles.Join(", ")]"
		displayed_text[FA_ICON_TOOLBOX] = tooltip_text.Join("\n")

	if(restricted_species)
		displayed_text[FA_ICON_DNA] = "Species Whitelist: [restricted_species.Join(", ")]"
	// SKYRAT EDIT ADDITION
	return displayed_text

/**
 * Returns a list of buttons that are shown in the loadout UI for customizing this item.
 *
 * Buttons contain
 * - 'L'abel: The text displayed beside the button
 * - act_key: The key that is sent to the loadout manager when the button is clicked,
 * for use in handle_loadout_action
 * - button_icon: The FontAwesome icon to display on the button
 * - active_key: In the loadout UI, this key is checked  in the user's loadout list for this item
 * to determine if the button is 'active' (green) or not (blue).
 * - active_text: Optional, if provided, the button appears to be a checkbox and this text is shown when 'active'
 * - inactive_text: Optional, if provided, the button appears to be a checkbox and this text is shown when not 'active'
 */
/datum/loadout_item/proc/get_ui_buttons() as /list
	SHOULD_CALL_PARENT(TRUE)

	var/list/button_list = list()

	if(can_be_greyscale)
		UNTYPED_LIST_ADD(button_list, list(
			"label" = "Recolor",
			"act_key" = "select_color",
			"button_icon" = FA_ICON_PALETTE,
			"active_key" = INFO_GREYSCALE,
		))

	if(can_be_named)
		UNTYPED_LIST_ADD(button_list, list(
			"label" = "Rename",
			"act_key" = "set_name",
			"button_icon" = FA_ICON_PEN,
			"active_key" = INFO_NAMED,
		))
		// SKYRAT EDIT BEGIN - Descriptions
		UNTYPED_LIST_ADD(button_list, list(
			"label" = "Change description",
			"act_key" = "set_desc",
			"button_icon" = FA_ICON_PEN,
			"active_key" = INFO_NAMED,
		))
		// SKYRAT EDIT END
	return button_list

/**
 * Returns a list of options this item can be reskinned into.
 */
/datum/loadout_item/proc/get_reskin_options() as /list
	if(!can_be_reskinned)
		return null

	var/list/reskins = list()

	for(var/skin in cached_reskin_options)
		UNTYPED_LIST_ADD(reskins, list(
			"name" = skin,
			"tooltip" = skin,
			"skin_icon_state" = cached_reskin_options[skin],
		))

	return reskins
