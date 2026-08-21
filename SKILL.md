# D365 Finance & Operations — Form Pattern Guide
### Part I: Selecting the right pattern · Part II: Implementing it as valid AxForm metadata · Part III: End-to-end checklist

Sources: Microsoft Learn ("Form patterns for migrated forms" and per-pattern reference pages), community write-ups by Wajahat Wasti (LinkedIn/Medium), and a verified `d365-form-builder` field guide built from real, working AxForm XML in a live environment.

**How to use this guide:**
- Starting a **new** form? Read Part I to pick a pattern, then Part III as a final sign-off checklist.
- **Hand-editing AxForm XML** (or debugging an "is not readable" compile error)? Go straight to Part II.
- **Migrating/inspecting** an existing form? Start at §2.2.

**Jump to:** [§1](#1-why-form-patterns-exist) Why patterns exist · [§2](#2-the-decision-framework--how-to-choose-a-pattern) Choosing a pattern · [§3](#3-applying-a-pattern-in-the-form-designer) Applying in the Designer · [§4](#4-required-properties--best-practice-bp-checks-per-pattern) BP checks · [§5](#5-manual-ux-checklist-not-bp-enforced) Manual UX checklist · [§6](#6-x-layer-conventions-event-handlers--extensions) X++ conventions · [§7](#7-verify-with-the-form-patterns-report) Form Patterns report · [§8](#8-quick-reference--canonical-example-forms-per-pattern) Canonical examples · [§9](#9-why-axform-xml-is-unforgiving) Why AxForm XML is unforgiving · [§10](#10-verified-control-type-mapping-field-type--gridgroup-control) Control-type mapping · [§11](#11-minimal-axform-skeleton-simple-list-pattern) Minimal skeleton · [§12](#12-wiring-a-new-form-so-its-actually-usable) Wiring a form · [§13](#13-post-mortem-how-is-not-readable-got-diagnosed-and-fixed) Post-mortem · [§14](#14-end-to-end-practical-checklist-for-a-new-reef-form) Final checklist

---

# Part I — Choosing a Pattern

## 1. Why form patterns exist

In D365 F&O, every form built on the **Design** node is expected to conform to one of a fixed set of **form patterns**. Patterns exist so that:

- Every form in the product (and every ISV/partner form) looks and behaves consistently — same ActionPane rules, same FastTab behavior, same filter placement.
- Microsoft's **Best Practice (BP) checker** can validate structural rules automatically (missing captions, wrong data source properties, etc.).
- The **Application Explorer / Form designer** can auto-generate skeleton controls for you once a pattern is applied.

Practically: pick the pattern **before** you start dragging controls onto the Design node (or, per Part II, before hand-writing the XML). Retrofitting a pattern onto an already-built ad-hoc form is painful — the BP warnings will not converge cleanly.

## 2. The decision framework — how to choose a pattern

Use three lenses, in this order.

### 2.1 What is the form's job?

| The form needs to… | Use this pattern |
|---|---|
| Let users create/edit/browse a master entity (customer, vendor, item) with many attributes grouped logically | **Details Master** (or **w/ Standard Tabs** if >15 FastTabs) |
| Show a transaction header plus its lines (sales order + lines, purchase order + lines) | **Details Transaction** |
| Present a browsable, searchable/filterable list, optionally with FactBoxes, with no 1:1 details form or with multiple backing details forms | **List Page** *(now discouraged when there's a 1:1 List↔Details relationship — merge into Details Master/Transaction instead)* |
| Maintain a simple reference/setup or log table, single grid, no parent/child relationships | **Simple List** |
| Maintain a medium-complexity entity — grid on one side, detail fields/fasttabs on the other, or up to 5 child collections | **Simple List & Details** (List Grid / Tabular Grid / Tree variant) |
| Show a single record's fields without a navigation list (e.g., a sub-form drilled into from a grid) | **Simple Details** (Toolbar+Fields / FastTabs / Standard Tabs / Panorama variant) |
| Collect or display a set of values then close (OK/Cancel) | **Dialog** (Basic / Read-Only / FastTabs / Tabs / Double Tabs variant) |
| Collect a *small* number of fields (<5) to provide context for one action | **Drop Dialog** |
| Show setup/parameters spanning many unrelated topics | **Table of Contents** |
| Walk the user through a fixed sequence of steps with Next/Previous | **Wizard** |
| Serve as a lookup grid/tree from a field | **Lookup** (Basic / w/Preview / w/Tabs variant) |
| Act as a landing/navigation page summarizing an area of the business, no primary data source | **Operational Workspace** |
| Show related info inside another form (right-hand panel) | **FactBox** (Card = fields, Grid = child collection) |
| A legacy migrated form you don't intend to redesign | **Task Single / Task Double** — *migration-only, never for new forms* |

**Note on the "how many fields → Simple List vs. Simple List & Details" threshold:** you'll see slightly different numbers depending on the source. Microsoft Learn's List Page guidance caps the grid at "fewer than 15 fields"; community guidance (Wajahat Wasti) and field-tested practice both point to Simple List being right for flat entities with **≤6 fields comfortably, up to ~15 tolerated**, with 0 parent/child relationships — beyond that, or once a second data source/child collection appears, move to Simple List & Details. Treat 15 as the hard ceiling and 6 as the "clearly still simple" comfort zone; use judgment in between based on whether the record genuinely needs a details pane.

### 2.2 If you're migrating/inspecting an existing form, read the metadata

Microsoft's guidance for pattern selection during migration is to inspect, in order:

1. **`Form.Design.Style`** property — it usually still names the legacy pattern that was targeted. Map it using the table below.
2. **Control names and layout** — FastTabs vs. plain Tabs, presence of a grid vs. fields-only, number/names of data sources.
3. **Number and names of data sources** — a header + a *…Line* data source strongly suggests Details Transaction, not Details Master.
4. **Run the form and look at it** — least reliable, but a useful sanity check against the metadata read.

`Form.Design.Style` → likely pattern:

| Style value | Pattern |
|---|---|
| DetailsFormMaster | Details Master |
| DetailsFormTransaction | Details Transaction |
| Dialog | Dialog |
| DropDialog | Drop Dialog |
| FormPart (fields only) | FactBox Card |
| FormPart (grid) | FactBox Grid |
| ListPage | List Page |
| Lookup | Lookup |
| SimpleList | Simple List |
| SimpleListDetails (2–3 nav fields) | Simple List & Details – List Grid |
| SimpleListDetails (4–5 nav fields) | Simple List & Details – Tabular Grid |
| SimpleListDetails (tree) | Simple List & Details – Tree |
| TableOfContents | Table of Contents |
| Auto + Overview/General tabs, single data source | Task Single |
| Auto + two sets of Overview/General/header+lines | Task Double |
| Auto + single-record focus | Simple Details |
| Auto + name ends "Lookup" | Lookup |
| Auto + single tab + Next/Previous | Wizard |
| Auto + name ends "Wizard" | Wizard |
| Auto + just a grid and buttons | Simple List |

**Style property lies sometimes** — cross-check:

| Declared Style | Actually might be… |
|---|---|
| DetailsFormMaster | DetailsFormTransaction, if there's a lines grid or controls named "*lines*" |
| SimpleList | SimpleListDetails, if there's more than a grid + custom filters |
| SimpleListDetails | SimpleList, if it's really just a grid + filters |
| SimpleList | ListPage, if there are many FactBoxes, or a corresponding Details form exists |

### 2.3 Rule-of-thumb sizing questions

Ask these three questions and the pattern usually falls out on its own:

1. **Is there a header + child lines relationship (parent/child data sources)?** → Details Transaction.
2. **Is this a master/reference entity edited by end users regularly, with many fields?** → Details Master (>15 FastTab groups → w/Standard Tabs variant).
3. **Is it just a flat list under ~10 fields with no real "detail" view?** → Simple List. Once you're past that (or you have a second data source/child collection), move to Simple List & Details.

If none of those fit and it's a one-off popup gathering input → Dialog or Drop Dialog (based on field count and whether it needs FastTabs/Tabs).

## 3. Applying a pattern in the Form Designer

1. Create the form and add your data source(s) first (pattern selection is easier once you know your data sources).
2. In the AOT / Visual Studio Application Explorer, right-click the **Design** node → **Apply pattern** → pick the pattern (and variant, if prompted).
3. Visual Studio scaffolds the skeleton nodes for you (ActionPane, SidePanel/Grid, Tab/FastTab containers, etc.) matching the pattern's high-level structure. (See Part II for exactly what that scaffolding looks like at the XML level.)

Example — **Details Master (basic)** high-level structure that gets scaffolded:

```
Design
 ├─ ActionPane
 ├─ SidePanel (Group)
 │   ├─ QuickFilter
 │   ├─ CustomFilters (Group) [optional]
 │   └─ NavigationList (Grid, Style=List)
 └─ MainTab (Tab, ShowTabs=No)
     ├─ DetailsTabPage
     │   ├─ TitleGroup (Group: HeaderTitle, EntityStatus[optional])
     │   └─ DetailsTab (Tab, Style=FastTabs) → repeating DetailsTabPage(s)
     └─ GridTabPage
         ├─ CustomFilterGroup (QuickFilter + OtherFilters)
         ├─ MainGrid
         └─ MainGridDefaultAction (CommandButton)
```

Example — **List Page** high-level structure:

```
Design
 ├─ ActionPane
 ├─ CustomFilter (Group: QuickFilter + OtherFilters[0..N])
 └─ Grid
```

### Fill each container using the correct sub-pattern

Top-level patterns are made of smaller, reusable **sub-patterns** applied to individual groups/containers. Right-click a container → **Apply pattern** to assign one of these when Visual Studio flags it as "unspecified" (search "unspecified" in the designer's control search box to find every container still needing one):

| Sub-pattern | Use for |
|---|---|
| Custom Filters / Custom & Quick Filters | Filter row above a grid |
| Fields and Field Groups | A container with only fields, responsive layout |
| Tabular Fields | Structured field layout, typically totals |
| Fill Text | One input control needing full width (e.g., Notes) |
| Horizontal Fields and Button Group | A field with an inline action button |
| Image Preview | Containers with image controls |
| Toolbar and List (single/double) | Actions above 1–2 grids |
| Toolbar and Fields | Actions above a set of fields |
| List Panel | Two lists with move-between-them UX |
| Nested Simple List & Details | Embedding a mini Simple List & Details inside a tab/group |
| Dimension Entry Control / Dimension Expression Builder | Tab pages holding only these financial-dimension controls |
| Workspace-related (Section Tiles, Related Links, Tabbed List, Stacked Chart, Power BI, Filter Group, Filters+Toolbar) | Sections inside an Operational Workspace |

## 4. Required properties / Best Practice (BP) checks per pattern

*Illustrative, not exhaustive — shown here for the three most common patterns. Every pattern has its own BP rule set; run Best Practices (see below) to see the full list for whichever pattern you're using.*

**Details Master**
- `Design.Caption` is not empty.
- Form is referenced by at least one menu item.
- Every `TabPage.Caption` is not empty.

**List Page**
- `Design.Caption` not empty; form referenced by a menu item.
- `TabPage.Caption` and `TabPage.DataSource` not empty.
- Primary data source: `AllowEdit = No`, `AllowCreate = No`, `AllowDelete = Yes`.
- `Grid.DefaultAction` references the button/menu item that opens the child (details) form.
- `Grid.DefaultLabelAction` references a label for the grid context-menu entry.

**Simple List**
- `Design.Caption` non-empty.
- `Design.Datasource` == `Grid.Datasource`.
- Grid has ≤15 fields.
- The primary key field has `IgnoreEDTRelation = Yes`.
- Form referenced by at least one menu item.
- Quick filter defaults to the name/description (or most identifying) column.
- **Important distinction:** a read-only log/audit table should set **both** `AllowCreate = No` and `AllowDelete = No` on its data source — this differs from the List Page convention above (`AllowCreate=No, AllowDelete=Yes`), since a log typically shouldn't be manually deletable through the UI either.

Run **Best Practices** on the form (or the whole model) before check-in — most pattern-conformance issues surface there.

## 5. Manual UX checklist (not BP-enforced)

These aren't caught by the compiler, so review them by eye:

- **General** (applies to almost every pattern): no duplicate New/Delete buttons; ActionPane/FastTab conventions per the *General Form Guidelines* page; Quick Filter gets initial focus where applicable.
- **List Page / Details Master grid view:** ID or Name is the first column depending on master vs. transactional entity; first textual column is a hyperlink (`Grid.DefaultAction`) into the details view; page title in plural form; fewer than 15 fields in the grid.
- **Details Master:** FastTabs (not plain tabs) group fields; first FastTab's content fully visible without scrolling by default; navigation-list rows should not wrap past 3 lines (usually just ID + Description, minimum 2 fields); page title format `"<ID> : <Description>"`.
- **Simple List & Details / Simple List:** field/data-source count decides List-Grid vs. Tabular-Grid vs. plain Simple List — see the threshold note in §2.1.
- **Wizard:** single tab control, Next/Previous/Finish flow, Next disabled until the current page's mandatory fields are complete.
- **Workspace:** no primary data source on the workspace form itself — content comes from Form Part Controls referencing separate part forms/patterns (Section Tiles, Section Chart, etc.).

## 6. X++ layer conventions (event handlers / extensions)

Regardless of pattern, prefer **Chain of Command (CoC)** classes or **form/data-source/control event handlers** over modifying OOTB forms directly — this is standard for Reef's `AND_RetailCustomization` / `ReefCustomization` style extensions:

```xpp
[ExtensionOf(formStr(CustTable))]
final class MyCustTable_Extension
{
    public void init()
    {
        next init();
        // pattern-aware customization: e.g. add a FastTab-scoped control,
        // or toggle visibility based on EntityStatus in the TitleGroup
    }
}
```

- For **Details Master/Transaction**, most customizations hook `DataSource.init/active/write/validateWrite`, or add fields inside an existing FastTab's `Fields and Field Groups` container rather than inventing a new container.
- For **List Page**, customizations typically extend `Grid` filtering/sorting or add ActionPane buttons — avoid re-adding New/Delete if the foundation already supplies them.
- For **Dialog/Drop Dialog**, the `dialog` class pattern (SysOperation framework `getFromDialog`/`dialog` methods) is preferred over the legacy `Object` dialog approach when the dialog triggers a batchable operation — this lines up with the SysOperation-stack style already used in your `ReefSlowMoving` module.

## 7. Verify with the Form Patterns report

Visual Studio can generate a **Form Patterns** report listing every form and its currently-applied pattern — useful to (a) find good real examples to copy (e.g., `CustTable` for Details Master, `SalesTable` for Details Transaction, `PaymTerm` for Simple List & Details) and (b) audit a whole model for forms still on legacy/incorrect patterns after migration.

## 8. Quick reference — canonical example forms per pattern

| Pattern | Reference OOTB form |
|---|---|
| Details Master | `CustTable` |
| Details Master w/Standard Tabs | `HcmWorker` |
| Details Transaction | `SalesTable` / `PurchTable` |
| Dialog – Basic | `ProjTableCreate` |
| Dialog – Read Only | `SalesTablePostings` |
| Drop Dialog | `CustCollectionsNewActivityAction` |
| FactBox Grid / Card | `ContactsInfoPart` / `CustStatisticsStatistics` |
| List Page | `SalesTableListPage` / `InventOnHandItemListPage` |
| Lookup Basic / w/Preview / w/Tabs | `SysLanguageLookup` / `HcmWorkerLookup` / `CaseCategoryLookup` |
| Simple List | `CustGroup` |
| Simple List & Details – List Grid | `PaymTerm` |
| Simple List & Details – Tabular Grid | `ExchangeRate` |
| Simple List & Details – Tree | `FiscalCalendars` |
| Table of Contents | `CustParameters` / `InventParameters` |
| Wizard | `WrkCtrBulkResReqEditWizard` |
| Operational Workspace | `FmClerkWorkspace` / `AssetWorkspace` |
| Task Single / Task Double (legacy only) | `LedgerJournalTable` / `HRMAbsenceTableHistory` |

---

# Part II — Implementing a Pattern as Valid AxForm XML

Everything above tells you *which* pattern to pick. This part covers what happens once you actually have to write or hand-edit the `AxForm` metadata file — where most real pain shows up, because the file is XML deserialized against a fixed, largely undocumented C# type hierarchy.

## 9. Why AxForm XML is unforgiving

A wrong `i:type` name or a missing required child element doesn't give you a line number or a field name in the compiler error — it fails the **entire file** with a generic message:

> Generate compiler metadata failed. Error = Metadata element 'X' of type 'AxForm' in model 'Y' is not readable. If the element is customized verify that the base file exists and is not corrupted.

This is the signature of "you guessed a control/element name that doesn't exist in the schema." It gives you nothing to go on directly, so the fix is procedural, not diagnostic-driven.

### The one rule that prevents almost every failure

**Never compose form XML from memory/pattern-extrapolation alone. Find a real, already-working form in the same model (or, failing that, anywhere under `K:\AosService\PackagesLocalDirectory\`) that uses the pattern/control you need, and copy its exact structure**, changing only names, table/field references, and labels. Every element the deserializer requires (including ones that seem redundant, like an empty `<Items />` on a combo box bound to an enum field) will already be present and correctly ordered.

Concretely, before trusting any `i:type` value or nested element you haven't personally seen in this codebase:

```
grep -rl "AxFormWhateverControl" "K:\AosService\PackagesLocalDirectory\<SomeModel>\...\AxForm"
```

Zero hits across the whole package tree (or even just the one candidate model) means: don't trust it. Either find a real example elsewhere, or drop the element/property and keep the form simpler. This is exactly how `AxFormEnumControl` was caught as invalid in a real session — it does not exist as a schema type. Grep for `<Type>ComboBox</Type>` style plain-text markers too; sometimes the surrounding property name search is easier than the `i:type` string itself.

## 10. Verified control-type mapping (field type → grid/group control)

Confirmed against real forms in a live environment (not just recalled from training):

| Field type | `i:type` | `<Type>` value | Notes |
|---|---|---|---|
| String / any string EDT | `AxFormStringControl` | `String` | |
| int | `AxFormIntegerControl` | `Integer` | |
| real | `AxFormRealControl` | `Real` | |
| utcDateTime | `AxFormDateTimeControl` | `DateTime` | |
| **Enum (non-NoYes)** | `AxFormComboBoxControl` | `ComboBox` | **Requires an empty `<Items />` child element even when bound via `<DataField>` to a real enum** — omitting it, or using the tempting-but-wrong `AxFormEnumControl`, breaks deserialization. |
| NoYes enum | `AxFormCheckBoxControl` | `CheckBox` | This package's own convention renders `NoYes` fields as checkboxes in grids, not combo boxes — mirror whatever the table's other forms already do for `NoYes` fields. |
| ActionPane container | `AxFormActionPaneControl` | `ActionPane` | |
| Grid container | `AxFormGridControl` | `Grid` | Has its own `<DataSource>` and `<Style>` (e.g. `Tabular`), plus a `<Controls>` list of the column controls. |
| Group container | `AxFormGroupControl` | `Group` | Used for the quick-filter bar; set `<Pattern>CustomAndQuickFilters</Pattern>`. |

**Unconfirmed in this codebase as of this writing** — verify with the grep technique above before using: `AxFormInt64Control` (Int64 fields), date-only `AxFormDateControl`, any `OrderBy`/sort metadata on `AxFormDataSource` (a guessed `<OrderBy><AxFormDataSourceSortField>...` block was tried and pulled back out for lack of any real example to confirm the shape — sort-by-column-click is a safe fallback when you can't verify the sort XML).

## 11. Minimal AxForm skeleton (Simple List pattern)

```xml
<?xml version="1.0" encoding="utf-8"?>
<AxForm xmlns:i="http://www.w3.org/2001/XMLSchema-instance" xmlns="Microsoft.Dynamics.AX.Metadata.V6">
	<Name>MyTableListPage</Name>
	<SourceCode>
		<Methods xmlns="">
			<Method>
				<Name>classDeclaration</Name>
				<Source><![CDATA[
[Form]
public class MyTableListPage extends FormRun
{
}
]]></Source>
			</Method>
		</Methods>
		<DataSources xmlns="" />
		<DataControls xmlns="" />
		<Members xmlns="" />
	</SourceCode>
	<DataSources>
		<AxFormDataSource xmlns="">
			<Name>MyTable</Name>
			<Table>MyTable</Table>
			<Fields>
				<AxFormDataSourceField><DataField>SomeField</DataField></AxFormDataSourceField>
				<!-- one per field actually used on the form, at minimum every grid column -->
			</Fields>
			<ReferencedDataSources />
			<AllowCreate>No</AllowCreate>   <!-- No/No for a system-written log; Yes/Yes for editable master data -->
			<AllowDelete>No</AllowDelete>
			<DataSourceLinks />
			<DerivedDataSources />
		</AxFormDataSource>
	</DataSources>
	<Design>
		<Pattern xmlns="">SimpleList</Pattern>
		<PatternVersion xmlns="">1.1</PatternVersion>
		<Style xmlns="">SimpleList</Style>
		<Controls xmlns="">
			<AxFormControl xmlns="" i:type="AxFormActionPaneControl">
				<Name>FormActionPaneControl1</Name>
				<Type>ActionPane</Type>
				<FormControlExtension i:nil="true" />
				<Controls />
			</AxFormControl>
			<AxFormControl xmlns="" i:type="AxFormGroupControl">
				<Name>FormGroupControl1</Name>
				<Pattern>CustomAndQuickFilters</Pattern>
				<PatternVersion>1.1</PatternVersion>
				<Type>Group</Type>
				<WidthMode>SizeToAvailable</WidthMode>
				<FormControlExtension i:nil="true" />
				<Controls>
					<AxFormControl>
						<Name>QuickFilterControl1</Name>
						<FormControlExtension>
							<Name>QuickFilterControl</Name>
							<ExtensionComponents />
							<ExtensionProperties>
								<AxFormControlExtensionProperty>
									<Name>targetControlName</Name><Type>String</Type><Value>FormGridControl1</Value>
								</AxFormControlExtensionProperty>
								<AxFormControlExtensionProperty>
									<Name>placeholderText</Name><Type>String</Type>
								</AxFormControlExtensionProperty>
								<AxFormControlExtensionProperty>
									<Name>defaultColumnName</Name><Type>String</Type><Value>MyTable_SomeField</Value>
								</AxFormControlExtensionProperty>
							</ExtensionProperties>
						</FormControlExtension>
					</AxFormControl>
				</Controls>
				<ArrangeMethod>HorizontalLeft</ArrangeMethod>
				<FrameType>None</FrameType>
				<Style>CustomFilter</Style>
				<ViewEditMode>Edit</ViewEditMode>
			</AxFormControl>
			<AxFormControl xmlns="" i:type="AxFormGridControl">
				<Name>FormGridControl1</Name>
				<Type>Grid</Type>
				<FormControlExtension i:nil="true" />
				<Controls>
					<AxFormControl xmlns="" i:type="AxFormStringControl">
						<Name>MyTable_SomeField</Name>
						<Type>String</Type>
						<FormControlExtension i:nil="true" />
						<DataField>SomeField</DataField>
						<DataSource>MyTable</DataSource>
					</AxFormControl>
					<!-- one AxFormControl per grid column, named "<DataSourceName>_<FieldName>" -->
				</Controls>
				<DataSource>MyTable</DataSource>
				<Style>Tabular</Style>
			</AxFormControl>
		</Controls>
	</Design>
	<Parts />
</AxForm>
```

Note the recurring quirk: most leaf elements need `xmlns=""` on them because the outer namespace is declared on the root, and `<FormControlExtension i:nil="true" />` is boilerplate on every plain column control (only the real extension — like the quick filter — has actual content in `FormControlExtension`).

## 12. Wiring a new form so it's actually usable

A form alone isn't reachable. It needs, all in the same model:

1. **`AxMenuItemDisplay`** (read-only viewing) or `AxMenuItemAction`/`AxMenuItemOutput` as appropriate — minimal shape:
   ```xml
   <AxMenuItemDisplay xmlns:i="http://www.w3.org/2001/XMLSchema-instance" xmlns="Microsoft.Dynamics.AX.Metadata.V1">
   	<Name>MyTableListPage</Name>
   	<Label>My table</Label>
   	<Object>MyTableListPage</Object>
   	<SubscriberAccessLevel><Read xmlns="">Allow</Read></SubscriberAccessLevel>
   </AxMenuItemDisplay>
   ```
2. **An entry in the relevant `AxMenu`** (`<AxMenuElementMenuItem><Name>/<MenuItemName>` set to the menu item's name) so a user can actually navigate to it — copy the placement convention of a sibling item that already lives near where the new one conceptually belongs (e.g. an inquiry/log form goes under an "Inquiry" submenu, not "Setup").
3. **`.rnrproj` `Content` entries** for both the `AxForm` and the `AxMenuItemDisplay`/Action, so they show up in the VS Solution Explorer project view (purely cosmetic/organizational — the real metadata lives in the model folder regardless, but an object left out of the `.rnrproj` is easy to lose track of and easy for a teammate to miss in review).

## 13. Post-mortem: how "is not readable" got diagnosed and fixed

A form failed to compile with exactly the generic error at the top of Part II. The offending file had `i:type="AxFormEnumControl"` on a grid column bound to a custom enum field — a plausible-looking name that does not exist in the schema. Because the deserializer fails the whole document on one bad polymorphic type, the error pointed at the form as a whole, not the control. The fix process, in order:

1. Confirmed via `grep -rn "AxFormEnumControl" <model>/AxForm` → zero hits anywhere in the package, including deep in standard Microsoft modules — strong signal it isn't a real type.
2. Searched instead for the literal text `<Type>Enum</Type>` and `<Type>ComboBox</Type>` across real forms to find how an actual enum field is bound in a grid.
3. Found a real example (`AxFormComboBoxControl` / `<Type>ComboBox</Type>`, with a trailing empty `<Items />`) in a sibling form in the same custom model, and copied that exact shape.
4. Rebuilt clean.

**Generalize this as the default workflow** any time a new/unfamiliar control or metadata element is needed: **grep for a real prior usage before writing the guess into the file.** This is the XML-level analog of Part I's "pick the pattern from real form metadata" guidance — at every layer of D365 F&O form work, copying a verified real example beats reconstructing the schema from memory.

---

# Part III — End-to-End Checklist

## 14. End-to-end practical checklist for a new Reef form

Run through this before check-in, regardless of which pattern you used — it just collects the "don't forget" items from Parts I and II into one pass.

- [ ] Data sources finalized before applying a pattern.
- [ ] Pattern chosen using the decision table in §2.1 (not copied blindly from a similar-looking form).
- [ ] Pattern applied via **Apply pattern** on the Design node, or (if hand-editing XML) scaffolded from a real working form of the same pattern per §9–§11.
- [ ] Every container search-flagged "unspecified" has a sub-pattern applied.
- [ ] Any unfamiliar `i:type`/element grepped against real forms in the package tree before it's trusted (§9, §13).
- [ ] Best Practices run clean (Caption, menu-item reference, DataSource AllowEdit/Create/Delete flags — set per the pattern *and* per the record type, e.g. read-only log vs. editable master data, §4).
- [ ] Manual UX checklist reviewed (grid field count/order, FastTabs vs. Tabs, page title format, no duplicate New/Delete, §5).
- [ ] Customization done via CoC/event handlers, not direct edits to OOTB objects (§6).
- [ ] Form referenced by a menu item, the menu item added to the correct `AxMenu`, and both added to `.rnrproj` (§12).

---

## Sources
- Microsoft Learn — *Form patterns for migrated forms*: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/user-interface/select-form-pattern
- Microsoft Learn — *List Page form pattern*: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/user-interface/list-page-form-pattern
- Microsoft Learn — *Details Master form pattern*: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/user-interface/details-master-form-pattern
- Microsoft Learn — *Simple List form pattern*: https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/user-interface/simple-list-form-pattern
- Microsoft Learn — *Simple List and Details form pattern*: https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/user-interface/simple-list-details-form-pattern
- Wajahat Wasti — *Form Patterns in Dynamics 365 FO* (Medium): https://medium.com/@wajahatwasti/form-patterns-in-dynamics-365-fo-form-templates-in-d365fo-a6e13c8cb92c
- Wajahat Wasti — *Types of Forms in D365 Finance and Operations* (LinkedIn Pulse): https://www.linkedin.com/pulse/types-forms-d365-finance-operations-wajahat-wasti
- Internal `d365-form-builder` field guide — verified AxForm XML control mapping and debugging workflow from a live D365 F&O environment.
