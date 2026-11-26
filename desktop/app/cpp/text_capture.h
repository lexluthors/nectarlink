// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QtCore/QString>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/QQuickItem>

// Takes keyboard focus so input methods (Chinese pinyin, Japanese, the emoji
// panel...) can compose, and gives out only finished text through
// `textCommitted`. Plain key presses still arrive as key events for QML's
// Keys handlers, so shortcuts and navigation keys keep working. Used where
// there is no text field of the app's own but IME text is wanted, such as
// "Type on phone".
class TextCapture : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT

    // Whether finished text from input methods is taken. Composing text
    // stays in the input method's own window.
    Q_PROPERTY(bool acceptsText READ acceptsText WRITE setAcceptsText NOTIFY acceptsTextChanged)

public:
    explicit TextCapture(QQuickItem *parent = nullptr);

    bool acceptsText() const { return m_acceptsText; }
    void setAcceptsText(bool on);

signals:
    void acceptsTextChanged();
    void textCommitted(const QString &text);

protected:
    void inputMethodEvent(QInputMethodEvent *event) override;
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override;

private:
    bool m_acceptsText = false;
};