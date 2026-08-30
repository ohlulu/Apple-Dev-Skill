# File Structure Patterns

## Overview

All UIKit types — view controllers, views, cells, and other subclasses — follow a consistent file structure that separates concerns into the main declaration and purpose-specific extensions. The main declaration answers "what is this object?", and extensions answer "what does it do?"

## Main Declaration

The main declaration contains only:
1. **Protocol conformances** — all listed on the class declaration line
2. **Properties** — ordered by access level: public → internal → private. UI properties use the simplest form that fits (see [UI Properties](#ui-properties)).
3. **Lifecycle methods** — after all properties

## Extensions by Responsibility

Everything outside properties and lifecycle goes into extensions, each with a single responsibility.

### Protocol Conformance Extensions

Each protocol gets its own extension. The conformance is declared on the class line — extensions only organize the implementation.

### Action Handler Extension

All `@objc` action methods live in a dedicated private extension.

### Layout Extension (Always Last)

Layout code is always the **last section** in the file. A single `private extension` contains `setupUI()`, which handles both view hierarchy assembly (`addSubview`) and constraint setup.

## UIViewController

```swift
class ProfileViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        return label
    }()

    lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        return tableView
    }()

    private let viewModel: ProfileViewModel

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.refresh()
    }
}

// MARK: - UITableViewDataSource
extension ProfileViewController {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = viewModel.items[indexPath.row].title
        return cell
    }
}

// MARK: - UITableViewDelegate
extension ProfileViewController {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Actions
private extension ProfileViewController {
    @objc func didTapSaveButton() {
        viewModel.save()
    }
}

// MARK: - Layout
private extension ProfileViewController {
    func setupUI() {
        view.addSubview(titleLabel)
        view.addSubview(tableView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
```

## UIView Subclass

The same structure applies. Key differences:
- Initializers (`init(frame:)` and `required init?(coder:)`) replace view controller lifecycle methods
- `layoutSubviews` sits with initializers in the main declaration
- Call `setupUI()` from the initializer

```swift
class AvatarView: UIView {

    lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }()

    private let badgeView = UIView()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.layer.cornerRadius = imageView.bounds.width / 2
    }
}

// MARK: - Layout
private extension AvatarView {
    func setupUI() {
        // addSubview + NSLayoutConstraint.activate, laid out against self —
        // same shape as the view controller example above
    }
}
```

## UITableViewCell / UICollectionViewCell

Cells follow the same pattern. Key differences:
- `contentView` is the layout root, not `self`
- `prepareForReuse()` sits with lifecycle methods
- Keep cell configuration minimal — the row/item controller or caller owns data binding

```swift
class AvatarCell: UITableViewCell {

    lazy var avatarView: AvatarView = AvatarView()
    lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        return label
    }()

    // MARK: - Lifecycle

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.imageView.image = nil
        nameLabel.text = nil
    }
}

// MARK: - Layout
private extension AvatarCell {
    func setupUI() {
        // Same shape as above, but every addSubview and anchor targets
        // contentView — never self.
    }
}
```

## UI Properties

UI properties should use the **simplest initializer form that keeps the code obvious**. Default access level is `internal`.

Use direct initialization when a single expression is enough:

```swift
lazy var subtotalRow: SummaryRow = SummaryRow(label: String(localized: "cashier.subtotal"))
```

Use **`lazy var` with a closure** only when inline configuration needs multiple statements:

```swift
lazy var avatarImageView: UIImageView = {
    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.layer.cornerRadius = 24
    return imageView
}()
```

Do **not** add `[unowned self]` or `[weak self]` to `lazy var` closures — the closure executes after `self` is fully initialized and is not retained beyond that point.

## Access Level Ordering

Within any scope (main declaration or extension), order members by access level:

1. `public` / `open`
2. `internal` (implicit)
3. `private`

**Exception**: when two members have a strong logical relationship (e.g., a public method and its private helper), keep them together regardless of access level.

This structure applies uniformly to `UIViewController`, `UIView`, `UITableViewCell`, `UICollectionViewCell`, and other UIKit subclasses. Type-specific lifecycle methods (`viewDidLoad`, `layoutSubviews`, `prepareForReuse`) sit in the lifecycle section of the main declaration.

## Generation Checklist

Before shipping a new UIKit subclass file:

- [ ] Main declaration contains only conformance list, properties (public → internal → private), and lifecycle methods
- [ ] Each protocol implementation lives in its own extension; conformances declared on the class line
- [ ] `@objc` actions grouped in one `private extension` (`// MARK: - Actions`)
- [ ] Layout (`setupUI()` — hierarchy + constraints) is the LAST `private extension` in the file
- [ ] UI properties use the simplest initializer form; closure form only for multi-statement config; no `[weak self]` in lazy closures
- [ ] Cells lay out against `contentView`; `prepareForReuse` resets reused state
- [ ] MARK anchors present so offset-based reads land on the right section
